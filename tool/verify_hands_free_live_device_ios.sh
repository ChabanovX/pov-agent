#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_hands_free_live_device_ios.sh <physical-device-id>" >&2
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

# `flutter test` disables iOS port publication and cannot attach to a
# CoreDevice local-network pairing. The repository integration driver keeps
# the same Dart assertions while publishing the VM service for either cable or
# wireless transport.
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/hands_free_live_microphone_test.dart \
  -d "$device_id" \
  --publish-port \
  --dart-define-from-file=.env.example \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=USE_RECORDED_AUDIO=false \
  --dart-define=RUN_HANDS_FREE_LIVE_MICROPHONE_TEST=true
