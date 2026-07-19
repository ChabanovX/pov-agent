#include "llama_bridge.h"

#include <algorithm>
#include <cstring>
#include <exception>
#include <new>
#include <string>
#include <vector>

#include "llama.h"

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

bool load_model_and_context(
    pov_llama_runtime* runtime,
    const char* model_path,
    int32_t context_tokens,
    int32_t batch_tokens,
    int32_t thread_count,
    int32_t gpu_layers) {
  auto model_parameters = llama_model_default_params();
  model_parameters.n_gpu_layers = gpu_layers;
  runtime->model = llama_model_load_from_file(model_path, model_parameters);
  if (runtime->model == nullptr) {
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
    release_loaded_model(runtime);
    return false;
  }

  runtime->vocabulary = llama_model_get_vocab(runtime->model);
  runtime->uses_gpu = gpu_layers > 0 && llama_supports_gpu_offload();
  return runtime->vocabulary != nullptr;
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

void release_sampler_noexcept(pov_llama_runtime* runtime) noexcept {
  if (runtime == nullptr) {
    return;
  }
  try {
    release_sampler(runtime);
  } catch (...) {
  }
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

#if defined(TARGET_OS_SIMULATOR) && TARGET_OS_SIMULATOR
    // Simulator Metal does not model iPhone memory or command scheduling. Keep
    // its acceptance lane deterministic and reserve Metal validation for device.
    gpu_layers = 0;
#elif defined(TARGET_OS_IOS) && TARGET_OS_IOS
    // This pinned Metal backend synchronizes with an API introduced in iOS 15.
    // Older deployment targets remain supported through the CPU runtime.
    bool metal_runtime_available = false;
    if (__builtin_available(iOS 15.0, *)) {
      metal_runtime_available = true;
    }
    if (!metal_runtime_available) {
      gpu_layers = 0;
    }
#endif

    const bool loaded_with_requested_backend = load_model_and_context(
        runtime,
        model_path,
        context_tokens,
        runtime->batch_tokens,
        thread_count,
        gpu_layers);
    if (!loaded_with_requested_backend && gpu_layers > 0) {
      release_loaded_model(runtime);
      runtime->uses_gpu = false;
      if (load_model_and_context(
              runtime,
              model_path,
              context_tokens,
              runtime->batch_tokens,
              thread_count,
              0)) {
        return runtime;
      }
    } else if (loaded_with_requested_backend) {
      return runtime;
    }

    copy_c_string("Could not load the GGUF model or create its context",
                  error_buffer, error_buffer_length);
    release_loaded_model(runtime);
    delete runtime;
    llama_backend_free();
    return nullptr;
  } catch (...) {
    if (runtime != nullptr) {
      release_sampler(runtime);
      release_loaded_model(runtime);
      delete runtime;
    }
    if (backend_initialized) {
      llama_backend_free();
    }
    throw;
  }
}

void pov_llama_destroy_impl(pov_llama_runtime* runtime) {
  if (runtime == nullptr) {
    return;
  }
  release_sampler(runtime);
  release_loaded_model(runtime);
  delete runtime;
  llama_backend_free();
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

  release_sampler(runtime);
  llama_memory_clear(llama_get_memory(runtime->context), true);

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
    return decode_status;
  }

  auto sampler_parameters = llama_sampler_chain_default_params();
  sampler_parameters.no_perf = true;
  runtime->sampler = llama_sampler_chain_init(sampler_parameters);
  if (runtime->sampler == nullptr) {
    set_error(runtime, "Could not allocate the llama.cpp sampler");
    return POV_LLAMA_SAMPLER_CREATE_FAILED;
  }
  if (!add_sampler(runtime, llama_sampler_init_top_k(top_k)) ||
      !add_sampler(runtime, llama_sampler_init_top_p(top_p, 1)) ||
      !add_sampler(runtime, llama_sampler_init_min_p(min_p, 1)) ||
      !add_sampler(runtime, llama_sampler_init_temp(temperature)) ||
      !add_sampler(runtime, llama_sampler_init_dist(seed))) {
    release_sampler(runtime);
    return POV_LLAMA_SAMPLER_CREATE_FAILED;
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
    release_sampler(runtime);
    return POV_LLAMA_COMPLETE;
  }

  const llama_token token = llama_sampler_sample(
      runtime->sampler,
      runtime->context,
      -1);
  if (llama_vocab_is_eog(runtime->vocabulary, token)) {
    release_sampler(runtime);
    return POV_LLAMA_COMPLETE;
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
    release_sampler(runtime);
    return POV_LLAMA_BUFFER_TOO_SMALL;
  }

  llama_token decoded_token = token;
  const llama_batch batch = llama_batch_get_one(&decoded_token, 1);
  if (llama_decode(runtime->context, batch) != 0) {
    set_error(runtime, "llama.cpp failed while decoding a generated token");
    release_sampler(runtime);
    return POV_LLAMA_DECODE_FAILED;
  }

  runtime->generated_tokens += 1;
  *output_length = piece_length;
  return POV_LLAMA_OK;
}

void pov_llama_cancel_generation_impl(pov_llama_runtime* runtime) {
  if (runtime == nullptr) {
    return;
  }
  release_sampler(runtime);
  if (runtime->context != nullptr) {
    llama_memory_clear(llama_get_memory(runtime->context), true);
  }
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

void pov_llama_destroy(pov_llama_runtime* runtime) {
  try {
    pov_llama_destroy_impl(runtime);
  } catch (...) {
    // Destruction is terminal and the exported C ABI cannot report failures.
  }
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
    release_sampler_noexcept(runtime);
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    release_sampler_noexcept(runtime);
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
    release_sampler_noexcept(runtime);
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    release_sampler_noexcept(runtime);
    set_unexpected_error(runtime, "Unexpected exception while decoding a token");
  }
  if (output_length != nullptr) {
    *output_length = 0;
  }
  return POV_LLAMA_UNEXPECTED;
}

void pov_llama_cancel_generation(pov_llama_runtime* runtime) {
  try {
    pov_llama_cancel_generation_impl(runtime);
  } catch (const std::exception& error) {
    set_unexpected_error(runtime, error.what());
  } catch (...) {
    set_unexpected_error(runtime, "Unexpected exception while cancelling generation");
  }
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
