#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_piper_android.sh <emulator-id>" >&2
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
  echo "error: $device_id uses $device_abi; the Piper lane requires arm64-v8a" >&2
  exit 65
fi

is_emulator="$(adb -s "$device_id" shell getprop ro.kernel.qemu | tr -d '\r')"
if [ "$is_emulator" != "1" ]; then
  echo "error: $device_id is not an Android Emulator" >&2
  exit 69
fi

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

flutter test integration_test/piper_speech_native_test.dart \
  -d "$device_id" \
  --dart-define-from-file=.env.example \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_NATIVE_PIPER_TEST=true
