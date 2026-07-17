# some_camera_with_llm

Flutter camera observation prototype backed by Ultralytics YOLO.

## Live camera

The default build uses the native camera surface and should be run on physical
hardware:

```sh
flutter run -d <device-id>
```

## Runtime video input

The recorded mode runs on the iOS Simulator without camera hardware:

```sh
flutter run -d <simulator-id> --dart-define=OBSERVATION_SOURCE=recorded
```

The ordinary app decodes a bundled MP4 at runtime through `AVAssetReader`,
encodes each selected frame as JPEG, and sends those bytes through the same
single-image `YOLO.predict` boundary used by repository integration tests. The
decoder is pull-based, so slow inference drops timing opportunities instead of
building an unbounded frame queue.

The iOS build bundles the pinned official `yolo26n` Core ML archive, so the
recorded mode and its acceptance lane do not depend on a first-run download.
Omit the define, or set `OBSERVATION_SOURCE=camera`, to restore camera input.

## Verification

Run the deterministic local gates on any development machine:

```sh
dart run tool/harness.dart verify --changed
```

The runtime video acceptance lane requires a booted iOS Simulator. It fails if
either native decoding/looping or the full MP4-to-YOLO app journey fails:

```sh
flutter devices
tool/verify_recorded_ios.sh <simulator-id>
```
