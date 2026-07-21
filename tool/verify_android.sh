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

device_abi="$(adb -s "$device_id" shell getprop ro.product.cpu.abi | tr -d '\r')"
if [ "$device_abi" != "arm64-v8a" ]; then
  echo "error: $device_id uses $device_abi; the acceptance lane requires arm64-v8a" >&2
  exit 65
fi

is_emulator="$(adb -s "$device_id" shell getprop ro.kernel.qemu | tr -d '\r')"
if [ "$is_emulator" = "1" ]; then
  device_sdk="$(adb -s "$device_id" shell getprop ro.build.version.sdk | tr -d '\r')"
  preview_sdk="$(adb -s "$device_id" shell getprop ro.build.version.preview_sdk | tr -d '\r')"
  device_codename="$(adb -s "$device_id" shell getprop ro.build.version.codename | tr -d '\r')"
  if [ "$device_sdk" != "36" ] || [ "${preview_sdk:-0}" != "0" ] || [ "$device_codename" != "REL" ]; then
    echo "error: emulator must use stable Android API 36, not a preview image" >&2
    exit 65
  fi

  tts_package="$(adb -s "$device_id" shell pm path com.google.android.tts 2>/dev/null | tr -d '\r')"
  case "$tts_package" in
    package:*) ;;
    *)
      echo "error: emulator lacks Google TTS; use system-images;android-36;google_apis_playstore;arm64-v8a" >&2
      exit 65
      ;;
  esac
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
  integration_test/system_speech_native_test.dart \
  -d "$device_id" \
  --dart-define-from-file=.env.example \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_RECORDED_YOLO_REPLAY_TEST=true \
  --dart-define=RUN_NATIVE_ASSISTANT_TEST=true \
  --dart-define=RUN_SYSTEM_SPEECH_TEST=true

flutter build apk --debug --target-platform android-arm64
adb -s "$device_id" install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$device_id" shell pm grant com.example.pov_agent android.permission.CAMERA
flutter test integration_test/camera_hardware_test.dart \
  -d "$device_id" \
  --dart-define=RUN_HARDWARE_CAMERA_TEST=true
