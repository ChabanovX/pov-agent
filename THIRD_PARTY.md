# Third-party native and model components

This file records reproducibility, runtime, and license information for the
project's selected plugins, native components, and model artifacts.

## flutter_tts

- Upstream: <https://github.com/dlutton/flutter_tts>
- Dart package: `flutter_tts` 4.2.5
- License: MIT

The application uses this plugin as a foreground bridge to the system speech
services provided by iOS and Android. It does not bundle a voice model or add
application-owned speech transport. Voice availability and any engine-level
network behavior remain device capabilities; the adapter validates an
installed English locale before speaking.

## sherpa-onnx

- Upstream: <https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.4>
- Dart package: [`sherpa_onnx` 1.13.4](https://pub.dev/packages/sherpa_onnx/versions/1.13.4)
- Pub package SHA-256: `889c03cf7a8788795e3a6d35bf9f20b66d1862ea7a73a1b6aaf6e450715c870a`
- License: Apache-2.0, retained in the package and
  [pinned upstream tag](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.4/LICENSE)

The application uses the package's platform FFI libraries for offline
VITS/Piper synthesis. Native model creation, generation, and destruction stay
on one worker isolate; the runtime is freed before the generated PCM is played.
The Apache-2.0 license recorded here applies to sherpa-onnx itself, not
automatically to every model or phonemizer component used with it.

## Piper LJSpeech medium-int8 voice bundle

- Archive:
  [`vits-piper-en_US-ljspeech-medium-int8.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ljspeech-medium-int8.tar.bz2)
- Exact archive size: `21090429` bytes
- Archive SHA-256: `24dc3bd77dd48c291e52c297878d3437c9492f245d823d7f6a06c4bbb67f4b6b`
- Exact expanded tar size: `37662720` bytes
- Extracted regular-file size: `37347875` bytes across `359` files
- Extracted tree SHA-256: `a38256a8fada764a1e7b450c5f307b7b5de159e137af1a6aae0b2326f355bc3b`
- Voice provenance:
  [Piper `en_US-ljspeech-medium` model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/ljspeech/medium/MODEL_CARD)
- Voice/dataset license record: public domain

The expanded tar is staged beside the cache and removed after every extraction
attempt; its exact size is included in the preflight free-space calculation.
The extracted-tree digest hashes sorted
`<file-sha256>  <relative-path>\n` records. Runtime acquisition verifies both
the compressed archive and this complete extracted tree before atomically
publishing the cache. The values are mirrored in [`.env.example`](.env.example).

The bundle also contains `espeak-ng-data`, which sherpa-onnx uses to phonemize
Piper input. [eSpeak NG is GPL-3.0-or-later](https://github.com/espeak-ng/espeak-ng#license-information).
That obligation is separate from the public-domain voice provenance and from
sherpa-onnx's Apache-2.0 license. Distribution of an application binary or
model bundle containing the eSpeak NG runtime or data therefore requires a
specific GPL compliance review.

## llama.cpp

- Upstream: <https://github.com/ggml-org/llama.cpp>
- Source location: `native/third_party/llama.cpp` git submodule
- Pinned commit: `47c786924ad1ab7e91da2cdc72fcdb563780c2bd`
- License: MIT, retained in the pinned submodule's `LICENSE` file

The app builds this source through `hook/build.dart`; the build does not fetch
llama.cpp sources, a prebuilt UI, or native binaries. The project-owned bridge
is linked as one bundled dynamic code asset. Its C ABI exports only model
create/destroy, generation begin/next/cancel, error-copy, and backend-diagnostic
functions.

The release build fixes the following relevant CMake options:

```text
BUILD_SHARED_LIBS=OFF
LLAMA_BUILD_COMMON=OFF
LLAMA_BUILD_APP=OFF
LLAMA_BUILD_EXAMPLES=OFF
LLAMA_BUILD_MTMD=OFF
LLAMA_BUILD_SERVER=OFF
LLAMA_BUILD_TESTS=OFF
LLAMA_BUILD_TOOLS=OFF
LLAMA_BUILD_UI=OFF
LLAMA_USE_PREBUILT_UI=OFF
LLAMA_OPENSSL=OFF
GGML_BACKEND_DL=OFF
GGML_NATIVE=OFF
GGML_OPENMP=OFF
GGML_BLAS=OFF
```

iOS builds additionally enable `GGML_ACCELERATE`, `GGML_METAL`, embedded Metal
shaders, and `GGML_METAL_NDEBUG`. They set `CMAKE_SYSTEM_NAME=iOS`, the selected
device or Simulator SDK and architecture, and Flutter's deployment target (iOS
13 for the app). The bridge links Apple Accelerate, Foundation, Metal, and
MetalKit. Physical iOS devices on iOS 15 and newer request Metal offload and
retry on CPU if model/context creation fails; iOS 13 and 14 use CPU directly
because the pinned Metal backend calls an iOS 15 API. The Simulator
intentionally uses CPU inference because Simulator Metal does not represent
physical-device memory or scheduling.

Android builds disable Accelerate, Metal, and llamafile and compile a portable
CPU backend through NDK `28.2.13676358`. The hook selects the ABI and minimum
API from Flutter's code-asset target, links the C++ runtime statically, and emits
one bundled `libpov_llama.so`. GPU layers are forced to zero before model load,
so Android does not perform a redundant failed load for a backend absent from
the artifact.

`LLAMA_BUILD_MTMD=OFF` is intentional for this text-only milestone. A later
visual adapter may extend the same project-owned bridge with the pinned
llama.cpp `libmtmd` target and a separately pinned `mmproj`; no VLM or hidden
image-inference dependency is included now.

## Qwen3-0.6B GGUF

- Model repository: <https://huggingface.co/unsloth/Qwen3-0.6B-GGUF>
- Pinned revision: `272676c9e0eb9f33a7719ba3d27482fbb445e801`
- File: `Qwen3-0.6B-Q4_K_M.gguf`
- Exact size: `396705472` bytes
- SHA-256: `ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a`
- License: Apache-2.0

The GGUF is not stored in Git and is never downloaded by the native build
hook. At runtime, the model store downloads the compile-time configured
artifact into an incomplete file, verifies its exact size and SHA-256, and only
then atomically publishes it to the application-support cache. A cached file is
loaded offline only after the same verification succeeds.

The defaults above are mirrored in `.env.example` and
`CompilationConstants`. Any deliberate compile-time artifact override must
provide a mutually consistent URL, revision, filename, size, checksum, and
license.
