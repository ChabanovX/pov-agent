#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tool/verify_assistant_device_ios.sh <physical-device-id>" >&2
  exit 64
fi

device_id="$1"

collect_descendants() {
  parent_pid="$1"
  for child_pid in $(pgrep -P "$parent_pid" 2>/dev/null || true); do
    collect_descendants "$child_pid"
    printf '%s\n' "$child_pid"
  done
}

signal_process_ids() {
  signal_name="$1"
  process_ids="$2"
  for process_id in $process_ids; do
    kill -"$signal_name" "$process_id" 2>/dev/null || true
  done
}

signal_process_tree() {
  signal_name="$1"
  root_pid="$2"
  process_ids="$(collect_descendants "$root_pid")
$root_pid"
  signal_process_ids "$signal_name" "$process_ids"
}

run_with_watchdog() {
  watchdog_seconds="$1"
  watchdog_label="$2"
  shift 2

  watchdog_directory="$(mktemp -d "${TMPDIR:-/tmp}/pov-assistant-watchdog.XXXXXX")"
  watchdog_marker="$watchdog_directory/timed-out"
  "$@" &
  command_pid="$!"
  (
    sleep "$watchdog_seconds" &
    delay_pid="$!"
    trap 'kill -TERM "$delay_pid" 2>/dev/null || true; wait "$delay_pid" 2>/dev/null || true; exit 0' HUP INT TERM
    wait "$delay_pid"
    trap - HUP INT TERM
    : >"$watchdog_marker"
    timed_out_process_ids="$(collect_descendants "$command_pid")
$command_pid"
    signal_process_ids TERM "$timed_out_process_ids"
    sleep 5
    signal_process_ids KILL "$timed_out_process_ids"
  ) &
  watchdog_pid="$!"

  trap 'signal_process_tree TERM "$command_pid"; kill -TERM "$watchdog_pid" 2>/dev/null || true' HUP INT TERM

  if wait "$command_pid"; then
    command_status=0
  else
    command_status="$?"
  fi
  if [ -f "$watchdog_marker" ]; then
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill -TERM "$watchdog_pid" 2>/dev/null || true
  fi
  wait "$watchdog_pid" 2>/dev/null || true
  trap - HUP INT TERM

  if [ -f "$watchdog_marker" ]; then
    echo "error: $watchdog_label exceeded ${watchdog_seconds}s" >&2
    rm -f "$watchdog_marker"
    rmdir "$watchdog_directory"
    return 124
  fi
  rmdir "$watchdog_directory"
  return "$command_status"
}

if xcrun simctl getenv "$device_id" SIMULATOR_UDID >/dev/null 2>&1; then
  echo "error: $device_id is an iOS Simulator, not a physical device" >&2
  exit 69
fi

if ! xcrun devicectl device info details --device "$device_id" >/dev/null; then
  echo "error: $device_id is not an available physical Apple device" >&2
  exit 69
fi

run_with_watchdog 2700 native-smoke \
  flutter test integration_test/assistant_native_smoke_test.dart \
  -d "$device_id" \
  --plain-name "verified Qwen runtime streams, cancels, unloads, and reloads" \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_NATIVE_ASSISTANT_TEST=true

run_with_watchdog 3600 hardware-soak \
  flutter test integration_test/assistant_hardware_soak_test.dart \
  -d "$device_id" \
  --dart-define=USE_RECORDED_VIDEO=true \
  --dart-define=RUN_ASSISTANT_HARDWARE_SOAK=true
