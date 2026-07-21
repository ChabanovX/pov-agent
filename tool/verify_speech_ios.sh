#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_speech_ios.sh <simulator-id>" >&2
  exit 64
fi

device_id="$1"
simulator_udid="$(xcrun simctl getenv "$device_id" SIMULATOR_UDID 2>/dev/null || true)"

if [ "$simulator_udid" != "$device_id" ]; then
  echo "error: $device_id is not a booted iOS Simulator" >&2
  exit 69
fi

flutter test integration_test/system_speech_native_test.dart \
  -d "$device_id" \
  --dart-define-from-file=.env.example \
  --dart-define=RUN_SYSTEM_SPEECH_TEST=true
