#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_android.sh <device-id>" >&2
  exit 64
fi

device_id="$1"
device_state="$(adb -s "$device_id" get-state 2>/dev/null || true)"

if [ "$device_state" != "device" ]; then
  echo "error: $device_id is not an available Android device" >&2
  exit 69
fi

installed_package_path="$(adb -s "$device_id" shell pm path com.example.pov_agent 2>/dev/null || true)"
if [ -n "$installed_package_path" ]; then
  adb -s "$device_id" uninstall com.example.pov_agent >/dev/null
fi

# One Flutter process owns every recorded-mode target. Besides avoiding device
# service churn, the initial clean install guarantees the Assistant target
# exercises first-run download before its transport-disabled restart.
flutter test \
  integration_test/model_storage_channel_test.dart \
  integration_test/recorded_video_decoder_test.dart \
  integration_test/recorded_yolo_replay_test.dart \
  integration_test/recorded_app_flow_test.dart \
  integration_test/assistant_native_smoke_test.dart \
  -d "$device_id" \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_RECORDED_YOLO_REPLAY_TEST=true \
  --dart-define=RUN_NATIVE_ASSISTANT_TEST=true

flutter build apk --debug --target-platform android-arm64
adb -s "$device_id" install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$device_id" shell pm grant com.example.pov_agent android.permission.CAMERA
flutter test integration_test/camera_hardware_test.dart \
  -d "$device_id" \
  --dart-define=RUN_HARDWARE_CAMERA_TEST=true
