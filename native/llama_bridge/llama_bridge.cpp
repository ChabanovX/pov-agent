#include "llama_bridge.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "ggml-backend.h"
#include "llama.h"
#include "llama-ext.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

struct pov_llama_runtime {
  llama_model* model = nullptr;
  llama_context* context = nullptr;
  const llama_vocab* vocabulary = nullptr;
  llama_sampler* sampler = nullptr;
  std::string error;
  int32_t batch_tokens = 0;
  int32_t max_tokens = 0;
  int32_t generated_tokens = 0;
  bool generation_active = false;
  bool uses_gpu = false;
};

namespace {

constexpr std::size_t kMaxCapturedLogBytes = 16384;
constexpr std::size_t kMaxFailureLogBytes = 1536;

void configure_ios_metal_capabilities() {
#if defined(TARGET_OS_IOS) && TARGET_OS_IOS
  static std::once_flag configure_once;
  std::call_once(configure_once, []() {
    // The bundled Metal 2.3 library cannot contain llama.cpp's BF16 or tensor
    // kernels, which require newer language revisions. Do not advertise
    // runtime capabilities that the precompiled library cannot provide.
    setenv("GGML_METAL_BF16_DISABLE", "1", 0);
    setenv("GGML_METAL_TENSOR_DISABLE", "1", 0);
  });
#endif
}

struct llama_log_dispatcher {
  std::mutex capture_mutex;
  std::mutex state_mutex;
  std::string captured_text;
  ggml_log_callback downstream_callback = nullptr;
  void* downstream_user_data = nullptr;
  bool capture_active = false;
};

void capture_llama_log(
    enum ggml_log_level level,
    const char* text,
    void* user_data) {
  auto* dispatcher = static_cast<llama_log_dispatcher*>(user_data);
  ggml_log_callback downstream_callback = nullptr;
  void* downstream_user_data = nullptr;
  if (dispatcher != nullptr) {
    std::lock_guard<std::mutex> lock(dispatcher->state_mutex);
    if (dispatcher->capture_active && text != nullptr) {
      dispatcher->captured_text.append(text);
      if (dispatcher->captured_text.size() > kMaxCapturedLogBytes) {
        dispatcher->captured_text.erase(
            0,
            dispatcher->captured_text.size() - kMaxCapturedLogBytes);
      }
    }
    downstream_callback = dispatcher->downstream_callback;
    downstream_user_data = dispatcher->downstream_user_data;
  }
  if (downstream_callback != nullptr) {
    downstream_callback(level, text, downstream_user_data);
  }
}

llama_log_dispatcher& installed_llama_log_dispatcher() {
  static llama_log_dispatcher dispatcher;
  static std::once_flag install_once;
  std::call_once(install_once, []() {
    // llama.cpp's callback setter is process-global and not thread-safe. The
    // bridge therefore installs one process-lifetime dispatcher before its
    // first backend initialization and never swaps stack-owned callback data.
    llama_log_get(
        &dispatcher.downstream_callback,
        &dispatcher.downstream_user_data);
    llama_log_set(capture_llama_log, &dispatcher);
  });
  return dispatcher;
}

class scoped_llama_log_capture {
 public:
  scoped_llama_log_capture()
      : dispatcher_(installed_llama_log_dispatcher()),
        capture_lock_(dispatcher_.capture_mutex) {
    // Only one model load owns the diagnostic buffer at a time. Other llama
    // logs may still pass through the permanent dispatcher and downstream sink.
    std::lock_guard<std::mutex> lock(dispatcher_.state_mutex);
    dispatcher_.captured_text.clear();
    dispatcher_.capture_active = true;
  }

  ~scoped_llama_log_capture() {
    std::lock_guard<std::mutex> lock(dispatcher_.state_mutex);
    dispatcher_.capture_active = false;
  }

  std::string snapshot() {
    std::lock_guard<std::mutex> lock(dispatcher_.state_mutex);
    return dispatcher_.captured_text;
  }

 private:
  llama_log_dispatcher& dispatcher_;
  std::unique_lock<std::mutex> capture_lock_;
};

std::string load_failure_message(
    bool requested_gpu,
    const char* stage,
    const std::string& native_log) {
  std::string message = requested_gpu ? "Metal " : "CPU ";
  message.append(stage);
  message.append(" failed");
  if (!native_log.empty()) {
    message.append(": ");
    const std::size_t first_byte = native_log.size() > kMaxFailureLogBytes
        ? native_log.size() - kMaxFailureLogBytes
        : 0;
    message.append(native_log.substr(first_byte));
  }
  return message;
}

std::string no_gpu_buffer_message(
    int32_t requested_gpu_layers,
    const std::string& native_log) {
  std::string message = "Metal offload verification failed: requested ";
  message.append(std::to_string(requested_gpu_layers));
  message.append(" GPU layers, but llama.cpp allocated no GPU model buffer");
  if (!native_log.empty()) {
    message.append(": ");
    const std::size_t first_byte = native_log.size() > kMaxFailureLogBytes
        ? native_log.size() - kMaxFailureLogBytes
        : 0;
    message.append(native_log.substr(first_byte));
  }
  return message;
}

void copy_string(const std::string& value, char* buffer, int32_t buffer_length) {
  if (buffer == nullptr || buffer_length <= 0) {
    return;
  }
  const auto copy_length = std::min<int32_t>(
      static_cast<int32_t>(value.size()),
      buffer_length - 1);
  std::memcpy(buffer, value.data(), copy_length);
  buffer[copy_length] = '\0';
}

void copy_c_string(
    const char* value,
    char* buffer,
    int32_t buffer_length) noexcept {
  if (value == nullptr || buffer == nullptr || buffer_length <= 0) {
    return;
  }
  const auto value_length = std::strlen(value);
  const auto copy_length = std::min<int32_t>(
      static_cast<int32_t>(value_length),
      buffer_length - 1);
  std::memcpy(buffer, value, copy_length);
  buffer[copy_length] = '\0';
}

void set_error(pov_llama_runtime* runtime, std::string message) {
  if (runtime != nullptr) {
    runtime->error = std::move(message);
  }
}

void set_unexpected_error(
    pov_llama_runtime* runtime,
    const char* message) noexcept {
  if (runtime == nullptr) {
    return;
  }
  try {
    runtime->error = message == nullptr ? "Unexpected native failure" : message;
  } catch (...) {
    // Diagnostics must never let a C++ exception cross the exported C ABI.
  }
}

void release_loaded_model(pov_llama_runtime* runtime) {
  if (runtime->context != nullptr) {
    llama_free(runtime->context);
    runtime->context = nullptr;
  }
  if (runtime->model != nullptr) {
    llama_model_free(runtime->model);
    runtime->model = nullptr;
  }
  runtime->vocabulary = nullptr;
}

bool model_has_gpu_weight_buffer(const llama_context* context) {
  // Backend availability is not proof of offload: llama.cpp may move
  // unsupported tensors to a CPU buffer. Inspect the pinned runtime's actual
  // model-memory placement so the device diagnostic reports real GPU use.
  for (const auto& [buffer_type, memory] :
       llama_get_memory_breakdown(context)) {
    if (memory.model == 0) {
      continue;
    }
    ggml_backend_dev_t device = ggml_backend_buft_get_device(buffer_type);
    if (device == nullptr) {
      continue;
    }
    const auto device_type = ggml_backend_dev_type(device);
    if (device_type == GGML_BACKEND_DEVICE_TYPE_GPU ||
        device_type == GGML_BACKEND_DEVICE_TYPE_IGPU) {
      return true;
    }
  }
  return false;
}

bool load_model_and_context(
    pov_llama_runtime* runtime,
    const char* model_path,
    int32_t context_tokens,
    int32_t batch_tokens,
    int32_t thread_count,
    int32_t gpu_layers,
    const char** failure_stage) {
  auto model_parameters = llama_model_default_params();
  model_parameters.n_gpu_layers = gpu_layers;
  runtime->model = llama_model_load_from_file(model_path, model_parameters);
  if (runtime->model == nullptr) {
    *failure_stage = "model load";
    return false;
  }

  auto context_parameters = llama_context_default_params();
  context_parameters.n_ctx = context_tokens;
  context_parameters.n_batch = batch_tokens;
  context_parameters.n_ubatch = batch_tokens;
  context_parameters.n_threads = thread_count;
  context_parameters.n_threads_batch = thread_count;
  context_parameters.no_perf = true;
  runtime->context = llama_init_from_model(runtime->model, context_parameters);
  if (runtime->context == nullptr) {
    *failure_stage = "context creation";
    release_loaded_model(runtime);
    return false;
  }

  runtime->vocabulary = llama_model_get_vocab(runtime->model);
  runtime->uses_gpu = gpu_layers > 0 &&
      model_has_gpu_weight_buffer(runtime->context);
  if (runtime->vocabulary == nullptr) {
    *failure_stage = "vocabulary access";
    return false;
  }
  return true;
}

void release_sampler(pov_llama_runtime* runtime) {
  if (runtime->sampler != nullptr) {
    llama_sampler_free(runtime->sampler);
    runtime->sampler = nullptr;
  }
  runtime->generation_active = false;
  runtime->generated_tokens = 0;
  runtime->max_tokens = 0;
}

int32_t quiesce_generation(
    pov_llama_runtime* runtime,
    bool clear_memory) noexcept {
  if (runtime == nullptr) {
    return POV_LLAMA_OK;
  }
  try {
    if (runtime->context != nullptr) {
      // llama_decode may return before Metal completes its command buffer. The
      // Dart generation contract cannot report completion or cancellation
      // until that final native step is safe to release or reuse.
      llama_synchronize(runtime->context);
    }
    release_sampler(runtime);
    if (clear_memory && runtime->context != nullptr) {
      llama_memory_clear(llama_get_memory(runtime->context), true);
    }
    return POV_LLAMA_OK;
  } catch (const std::exception& error) {
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    set_unexpected_error(
        runtime,
        "Unexpected exception while quiescing native generation");
  }
  return POV_LLAMA_UNEXPECTED;
}

int32_t quiesce_then_return(
    pov_llama_runtime* runtime,
    bool clear_memory,
    int32_t status_after_success) noexcept {
  const int32_t cleanup_status = quiesce_generation(runtime, clear_memory);
  return cleanup_status == POV_LLAMA_OK
      ? status_after_success
      : cleanup_status;
}

bool add_sampler(pov_llama_runtime* runtime, llama_sampler* sampler) {
  if (sampler == nullptr) {
    set_error(runtime, "Could not allocate a llama.cpp sampling stage");
    return false;
  }
  llama_sampler_chain_add(runtime->sampler, sampler);
  return true;
}

int32_t tokenize_prompt(
    pov_llama_runtime* runtime,
    const char* prompt,
    std::vector<llama_token>* tokens) {
  const auto prompt_length = static_cast<int32_t>(std::strlen(prompt));
  const int32_t required = -llama_tokenize(
      runtime->vocabulary,
      prompt,
      prompt_length,
      nullptr,
      0,
      true,
      true);
  if (required <= 0) {
    set_error(runtime, "llama.cpp could not measure the prompt tokens");
    return POV_LLAMA_TOKENIZE_FAILED;
  }

  tokens->resize(required);
  const int32_t written = llama_tokenize(
      runtime->vocabulary,
      prompt,
      prompt_length,
      tokens->data(),
      required,
      true,
      true);
  if (written != required) {
    set_error(runtime, "llama.cpp could not tokenize the complete prompt");
    return POV_LLAMA_TOKENIZE_FAILED;
  }
  return POV_LLAMA_OK;
}

int32_t decode_prompt(
    pov_llama_runtime* runtime,
    const std::vector<llama_token>& tokens) {
  for (int32_t offset = 0; offset < static_cast<int32_t>(tokens.size());) {
    const int32_t count = std::min<int32_t>(
        runtime->batch_tokens,
        static_cast<int32_t>(tokens.size()) - offset);
    const llama_batch batch = llama_batch_get_one(
        const_cast<llama_token*>(tokens.data()) + offset,
        count);
    if (llama_decode(runtime->context, batch) != 0) {
      set_error(runtime, "llama.cpp failed while decoding the prompt");
      return POV_LLAMA_DECODE_FAILED;
    }
    offset += count;
  }
  return POV_LLAMA_OK;
}

}  // namespace

pov_llama_runtime* pov_llama_create_impl(
    const char* model_path,
    int32_t context_tokens,
    int32_t batch_tokens,
    int32_t thread_count,
    int32_t gpu_layers,
    char* error_buffer,
    int32_t error_buffer_length) {
  pov_llama_runtime* runtime = nullptr;
  bool backend_initialized = false;
  try {
    if (model_path == nullptr || context_tokens <= 0 || batch_tokens <= 0 ||
        thread_count <= 0 || gpu_layers < 0) {
      copy_c_string("Invalid llama.cpp runtime configuration", error_buffer,
                    error_buffer_length);
      return nullptr;
    }

    scoped_llama_log_capture native_log;
    configure_ios_metal_capabilities();
    llama_backend_init();
    backend_initialized = true;
    runtime = new (std::nothrow) pov_llama_runtime();
    if (runtime == nullptr) {
      copy_c_string("Could not allocate the llama.cpp runtime", error_buffer,
                    error_buffer_length);
      llama_backend_free();
      return nullptr;
    }
    runtime->batch_tokens = std::min(batch_tokens, context_tokens);

    const int32_t requested_gpu_layers = gpu_layers;
    std::string backend_diagnostic;

#if defined(TARGET_OS_SIMULATOR) && TARGET_OS_SIMULATOR
    // Simulator Metal does not model iPhone memory or command scheduling. Keep
    // its acceptance lane deterministic and reserve Metal validation for device.
    if (gpu_layers > 0) {
      backend_diagnostic = "Metal disabled by iOS Simulator policy; requested ";
      backend_diagnostic.append(std::to_string(gpu_layers));
      backend_diagnostic.append(" GPU layers");
    }
    gpu_layers = 0;
#elif defined(TARGET_OS_IOS) && TARGET_OS_IOS
    // This pinned Metal backend synchronizes with an API introduced in iOS 15.
    // Older deployment targets remain supported through the CPU runtime.
    bool metal_runtime_available = false;
    if (__builtin_available(iOS 15.0, *)) {
      metal_runtime_available = true;
    }
    if (!metal_runtime_available) {
      if (gpu_layers > 0) {
        backend_diagnostic =
            "Metal disabled because the runtime requires iOS 15 or newer";
      }
      gpu_layers = 0;
    }
#endif

    const char* failure_stage = "runtime initialization";
    const bool requested_gpu = gpu_layers > 0;
    const bool loaded_with_requested_backend = load_model_and_context(
        runtime,
        model_path,
        context_tokens,
        runtime->batch_tokens,
        thread_count,
        gpu_layers,
        &failure_stage);
    if (loaded_with_requested_backend &&
        (!requested_gpu || runtime->uses_gpu)) {
      copy_string(backend_diagnostic, error_buffer, error_buffer_length);
      return runtime;
    }

    if (requested_gpu) {
      const std::string metal_log = native_log.snapshot();
      if (loaded_with_requested_backend) {
        backend_diagnostic =
            no_gpu_buffer_message(requested_gpu_layers, metal_log);
      } else {
        backend_diagnostic = "Requested ";
        backend_diagnostic.append(std::to_string(requested_gpu_layers));
        backend_diagnostic.append(" GPU layers; ");
        backend_diagnostic.append(
            load_failure_message(true, failure_stage, metal_log));
      }
      release_loaded_model(runtime);
      runtime->uses_gpu = false;
      failure_stage = "model load";
      if (load_model_and_context(
          runtime,
          model_path,
          context_tokens,
          runtime->batch_tokens,
          thread_count,
          0,
          &failure_stage)) {
        copy_string(backend_diagnostic, error_buffer, error_buffer_length);
        return runtime;
      }
    }

    std::string diagnostic = load_failure_message(
        false,
        failure_stage,
        native_log.snapshot());
    if (!backend_diagnostic.empty()) {
      diagnostic.insert(0, "; ");
      diagnostic.insert(0, backend_diagnostic);
    }
    release_loaded_model(runtime);
    copy_string(diagnostic, error_buffer, error_buffer_length);
    delete runtime;
    llama_backend_free();
    return nullptr;
  } catch (...) {
    if (runtime != nullptr) {
      (void) quiesce_generation(runtime, false);
      release_loaded_model(runtime);
      delete runtime;
    }
    if (backend_initialized) {
      llama_backend_free();
    }
    throw;
  }
}

int32_t pov_llama_destroy_impl(pov_llama_runtime* runtime) {
  if (runtime == nullptr) {
    return POV_LLAMA_OK;
  }
  const int32_t cleanup_status = quiesce_generation(runtime, false);
  if (cleanup_status != POV_LLAMA_OK) {
    return cleanup_status;
  }
  release_loaded_model(runtime);
  llama_backend_free();
  delete runtime;
  return POV_LLAMA_OK;
}

int32_t pov_llama_begin_generation_impl(
    pov_llama_runtime* runtime,
    const char* prompt,
    int32_t max_tokens,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    uint32_t seed) {
  if (runtime == nullptr || prompt == nullptr || max_tokens <= 0 ||
      temperature <= 0.0f || top_p <= 0.0f || top_p > 1.0f || top_k <= 0 ||
      min_p < 0.0f || min_p > 1.0f) {
    set_error(runtime, "Invalid generation configuration");
    return POV_LLAMA_INVALID_ARGUMENT;
  }
  if (runtime->context == nullptr || runtime->vocabulary == nullptr) {
    set_error(runtime, "The llama.cpp runtime is not loaded");
    return POV_LLAMA_NOT_READY;
  }

  const int32_t previous_generation_status = quiesce_generation(runtime, true);
  if (previous_generation_status != POV_LLAMA_OK) {
    return previous_generation_status;
  }

  std::vector<llama_token> prompt_tokens;
  const int32_t tokenize_status = tokenize_prompt(runtime, prompt, &prompt_tokens);
  if (tokenize_status != POV_LLAMA_OK) {
    return tokenize_status;
  }
  if (static_cast<int32_t>(prompt_tokens.size()) + max_tokens >
      static_cast<int32_t>(llama_n_ctx(runtime->context))) {
    set_error(runtime, "The prompt and response exceed the configured context");
    return POV_LLAMA_PROMPT_TOO_LONG;
  }

  const int32_t decode_status = decode_prompt(runtime, prompt_tokens);
  if (decode_status != POV_LLAMA_OK) {
    return quiesce_then_return(runtime, true, decode_status);
  }

  auto sampler_parameters = llama_sampler_chain_default_params();
  sampler_parameters.no_perf = true;
  runtime->sampler = llama_sampler_chain_init(sampler_parameters);
  if (runtime->sampler == nullptr) {
    set_error(runtime, "Could not allocate the llama.cpp sampler");
    return quiesce_then_return(
        runtime,
        true,
        POV_LLAMA_SAMPLER_CREATE_FAILED);
  }
  if (!add_sampler(runtime, llama_sampler_init_top_k(top_k)) ||
      !add_sampler(runtime, llama_sampler_init_top_p(top_p, 1)) ||
      !add_sampler(runtime, llama_sampler_init_min_p(min_p, 1)) ||
      !add_sampler(runtime, llama_sampler_init_temp(temperature)) ||
      !add_sampler(runtime, llama_sampler_init_dist(seed))) {
    return quiesce_then_return(
        runtime,
        true,
        POV_LLAMA_SAMPLER_CREATE_FAILED);
  }

  runtime->max_tokens = max_tokens;
  runtime->generated_tokens = 0;
  runtime->generation_active = true;
  runtime->error.clear();
  return POV_LLAMA_OK;
}

int32_t pov_llama_next_token_impl(
    pov_llama_runtime* runtime,
    uint8_t* output_buffer,
    int32_t output_buffer_length,
    int32_t* output_length) {
  if (runtime == nullptr || output_buffer == nullptr ||
      output_buffer_length <= 0 || output_length == nullptr) {
    set_error(runtime, "Invalid token output buffer");
    return POV_LLAMA_INVALID_ARGUMENT;
  }
  *output_length = 0;
  if (!runtime->generation_active || runtime->sampler == nullptr) {
    set_error(runtime, "No generation is active");
    return POV_LLAMA_NOT_READY;
  }
  if (runtime->generated_tokens >= runtime->max_tokens) {
    return quiesce_then_return(runtime, false, POV_LLAMA_COMPLETE);
  }

  const llama_token token = llama_sampler_sample(
      runtime->sampler,
      runtime->context,
      -1);
  if (llama_vocab_is_eog(runtime->vocabulary, token)) {
    return quiesce_then_return(runtime, false, POV_LLAMA_COMPLETE);
  }

  const bool render_special_tokens = false;
  const int32_t piece_length = llama_token_to_piece(
      runtime->vocabulary,
      token,
      reinterpret_cast<char*>(output_buffer),
      output_buffer_length,
      0,
      render_special_tokens);
  if (piece_length < 0 || piece_length > output_buffer_length) {
    set_error(runtime, "The token piece exceeded the bridge buffer");
    return quiesce_then_return(
        runtime,
        false,
        POV_LLAMA_BUFFER_TOO_SMALL);
  }

  llama_token decoded_token = token;
  const llama_batch batch = llama_batch_get_one(&decoded_token, 1);
  if (llama_decode(runtime->context, batch) != 0) {
    set_error(runtime, "llama.cpp failed while decoding a generated token");
    return quiesce_then_return(runtime, false, POV_LLAMA_DECODE_FAILED);
  }

  runtime->generated_tokens += 1;
  *output_length = piece_length;
  return POV_LLAMA_OK;
}

int32_t pov_llama_cancel_generation_impl(pov_llama_runtime* runtime) {
  if (runtime == nullptr) {
    return POV_LLAMA_OK;
  }
  return quiesce_generation(runtime, true);
}

int32_t pov_llama_copy_error_impl(
    const pov_llama_runtime* runtime,
    char* error_buffer,
    int32_t error_buffer_length) {
  if (runtime == nullptr || error_buffer == nullptr || error_buffer_length <= 0) {
    return POV_LLAMA_INVALID_ARGUMENT;
  }
  copy_string(runtime->error, error_buffer, error_buffer_length);
  return static_cast<int32_t>(runtime->error.size());
}

int32_t pov_llama_uses_gpu_impl(const pov_llama_runtime* runtime) {
  return runtime != nullptr && runtime->uses_gpu ? 1 : 0;
}

pov_llama_runtime* pov_llama_create(
    const char* model_path,
    int32_t context_tokens,
    int32_t batch_tokens,
    int32_t thread_count,
    int32_t gpu_layers,
    char* error_buffer,
    int32_t error_buffer_length) {
  try {
    return pov_llama_create_impl(
        model_path,
        context_tokens,
        batch_tokens,
        thread_count,
        gpu_layers,
        error_buffer,
        error_buffer_length);
  } catch (const std::exception& error) {
    copy_c_string(error.what(), error_buffer, error_buffer_length);
  } catch (...) {
    copy_c_string(
        "Unexpected exception while creating the llama.cpp runtime",
        error_buffer,
        error_buffer_length);
  }
  return nullptr;
}

int32_t pov_llama_destroy(pov_llama_runtime* runtime) {
  try {
    return pov_llama_destroy_impl(runtime);
  } catch (const std::exception& error) {
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    set_unexpected_error(
        runtime,
        "Unexpected exception while destroying the llama.cpp runtime");
  }
  return POV_LLAMA_UNEXPECTED;
}

int32_t pov_llama_begin_generation(
    pov_llama_runtime* runtime,
    const char* prompt,
    int32_t max_tokens,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    uint32_t seed) {
  try {
    return pov_llama_begin_generation_impl(
        runtime,
        prompt,
        max_tokens,
        temperature,
        top_p,
        top_k,
        min_p,
        seed);
  } catch (const std::exception& error) {
    (void) quiesce_generation(runtime, true);
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    (void) quiesce_generation(runtime, true);
    set_unexpected_error(runtime, "Unexpected exception while starting generation");
  }
  return POV_LLAMA_UNEXPECTED;
}

int32_t pov_llama_next_token(
    pov_llama_runtime* runtime,
    uint8_t* output_buffer,
    int32_t output_buffer_length,
    int32_t* output_length) {
  try {
    return pov_llama_next_token_impl(
        runtime,
        output_buffer,
        output_buffer_length,
        output_length);
  } catch (const std::exception& error) {
    (void) quiesce_generation(runtime, true);
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    (void) quiesce_generation(runtime, true);
    set_unexpected_error(runtime, "Unexpected exception while decoding a token");
  }
  if (output_length != nullptr) {
    *output_length = 0;
  }
  return POV_LLAMA_UNEXPECTED;
}

int32_t pov_llama_cancel_generation(pov_llama_runtime* runtime) {
  try {
    return pov_llama_cancel_generation_impl(runtime);
  } catch (const std::exception& error) {
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    set_unexpected_error(runtime, "Unexpected exception while cancelling generation");
  }
  return POV_LLAMA_UNEXPECTED;
}

int32_t pov_llama_copy_error(
    const pov_llama_runtime* runtime,
    char* error_buffer,
    int32_t error_buffer_length) {
  try {
    return pov_llama_copy_error_impl(
        runtime,
        error_buffer,
        error_buffer_length);
  } catch (...) {
    copy_c_string(
        "Unexpected exception while reading the native diagnostic",
        error_buffer,
        error_buffer_length);
    return POV_LLAMA_UNEXPECTED;
  }
}

int32_t pov_llama_uses_gpu(const pov_llama_runtime* runtime) {
  try {
    return pov_llama_uses_gpu_impl(runtime);
  } catch (...) {
    return 0;
  }
}
