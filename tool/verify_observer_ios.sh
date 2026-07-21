#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_observer_ios.sh <simulator-id>" >&2
  exit 64
fi

device_id="$1"
app_path="build/ios/iphonesimulator/Runner.app"
simulator_udid="$(xcrun simctl getenv "$device_id" SIMULATOR_UDID 2>/dev/null || true)"

verify_metal_toolchain() {
  if ! xcrun --find metal >/dev/null 2>&1 ||
    ! xcrun --find metallib >/dev/null 2>&1; then
    echo "error: Xcode's Metal Toolchain component is unavailable" >&2
    echo "install it with: xcodebuild -downloadComponent MetalToolchain" >&2
    exit 69
  fi
}

verify_precompiled_metallib() {
  metallib_path="$app_path/default.metallib"
  native_path="$app_path/Frameworks/pov_llama.framework/pov_llama"

  if [ ! -s "$metallib_path" ]; then
    echo "error: Xcode did not package a non-empty $metallib_path" >&2
    exit 70
  fi
  if [ ! -s "$native_path" ]; then
    echo "error: Flutter did not package a non-empty $native_path" >&2
    exit 70
  fi
  metallib_magic="$(dd if="$metallib_path" bs=4 count=1 2>/dev/null)"
  if [ "$metallib_magic" != 'MTLB' ]; then
    echo "error: $metallib_path is not a compiled Metal library" >&2
    exit 70
  fi
  if ! native_load_commands="$(otool -l "$native_path")"; then
    echo "error: otool could not inspect $native_path" >&2
    exit 70
  fi
  if printf '%s\n' "$native_load_commands" | grep -q '__ggml_metallib'; then
    echo "error: $native_path still embeds runtime-compiled Metal source" >&2
    exit 70
  fi

  echo "OBSERVER_IOS_BUILD stage=precompiled_metallib path=$metallib_path"
}

if [ "$simulator_udid" != "$device_id" ]; then
  echo "error: $device_id is not a booted iOS Simulator" >&2
  exit 69
fi

verify_metal_toolchain

flutter test integration_test/observer_native_soak_test.dart \
  -d "$device_id" \
  --dart-define-from-file=.env.example \
  --dart-define=QWEN_RANDOM_SEED=42 \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_NATIVE_OBSERVER_TEST=true

verify_precompiled_metallib
