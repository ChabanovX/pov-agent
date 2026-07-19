#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_assistant_ios.sh <simulator-id>" >&2
  exit 64
fi

device_id="$1"
simulator_udid="$(xcrun simctl getenv "$device_id" SIMULATOR_UDID 2>/dev/null || true)"

if [ "$simulator_udid" != "$device_id" ]; then
  echo "error: $device_id is not a booted iOS Simulator" >&2
  exit 69
fi

flutter test integration_test/assistant_native_smoke_test.dart \
  -d "$device_id" \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_NATIVE_ASSISTANT_TEST=true
