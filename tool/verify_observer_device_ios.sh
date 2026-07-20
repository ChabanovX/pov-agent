#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_observer_device_ios.sh <physical-device-id>" >&2
  exit 64
fi

device_id="$1"

if xcrun simctl getenv "$device_id" SIMULATOR_UDID >/dev/null 2>&1; then
  echo "error: $device_id is an iOS Simulator, not a physical device" >&2
  exit 69
fi

if ! xcrun devicectl device info details --device "$device_id" >/dev/null; then
  echo "error: $device_id is not an available physical Apple device" >&2
  exit 69
fi

flutter test integration_test/camera_hardware_test.dart \
  -d "$device_id" \
  --dart-define=RUN_HARDWARE_CAMERA_TEST=true

flutter test integration_test/observer_native_soak_test.dart \
  -d "$device_id" \
  --dart-define=RUN_LIVE_OBSERVER_TEST=true \
  --dart-define=REQUIRE_GPU_OBSERVER=true

flutter test integration_test/observer_native_soak_test.dart \
  -d "$device_id" \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_NATIVE_OBSERVER_TEST=true \
  --dart-define=REQUIRE_GPU_OBSERVER=true
