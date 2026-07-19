#ifndef POV_LLAMA_BRIDGE_H
#define POV_LLAMA_BRIDGE_H

#include <stdint.h>

#if defined(_WIN32)
#define POV_LLAMA_EXPORT __declspec(dllexport)
#else
#define POV_LLAMA_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pov_llama_runtime pov_llama_runtime;

enum pov_llama_status {
  POV_LLAMA_OK = 0,
  POV_LLAMA_COMPLETE = 1,
  POV_LLAMA_INVALID_ARGUMENT = -1,
  POV_LLAMA_MODEL_LOAD_FAILED = -2,
  POV_LLAMA_CONTEXT_CREATE_FAILED = -3,
  POV_LLAMA_NOT_READY = -4,
  POV_LLAMA_PROMPT_TOO_LONG = -5,
  POV_LLAMA_TOKENIZE_FAILED = -6,
  POV_LLAMA_DECODE_FAILED = -7,
  POV_LLAMA_SAMPLER_CREATE_FAILED = -8,
  POV_LLAMA_BUFFER_TOO_SMALL = -9,
  POV_LLAMA_UNEXPECTED = -10,
};

POV_LLAMA_EXPORT pov_llama_runtime* pov_llama_create(
    const char* model_path,
    int32_t context_tokens,
    int32_t batch_tokens,
    int32_t thread_count,
    int32_t gpu_layers,
    char* error_buffer,
    int32_t error_buffer_length);

POV_LLAMA_EXPORT int32_t pov_llama_destroy(pov_llama_runtime* runtime);

POV_LLAMA_EXPORT int32_t pov_llama_begin_generation(
    pov_llama_runtime* runtime,
    const char* prompt,
    int32_t max_tokens,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    uint32_t seed);

POV_LLAMA_EXPORT int32_t pov_llama_next_token(
    pov_llama_runtime* runtime,
    uint8_t* output_buffer,
    int32_t output_buffer_length,
    int32_t* output_length);

POV_LLAMA_EXPORT int32_t pov_llama_cancel_generation(
    pov_llama_runtime* runtime);

POV_LLAMA_EXPORT int32_t pov_llama_copy_error(
    const pov_llama_runtime* runtime,
    char* error_buffer,
    int32_t error_buffer_length);

POV_LLAMA_EXPORT int32_t pov_llama_uses_gpu(
    const pov_llama_runtime* runtime);

#ifdef __cplusplus
}
#endif

#endif
