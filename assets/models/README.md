# Bundled YOLO models

The platform-specific official Ultralytics YOLO26 nano models are bundled so
the default detector never depends on a first-run model download.

## iOS Core ML

`yolo26n.mlpackage.zip` comes from the `yolo-ios-app` v8.3.0 release:

https://github.com/ultralytics/yolo-ios-app/releases/tag/v8.3.0

The archive is bundled at `assets/models/yolo26n.mlpackage.zip`, which is the
offline asset path resolved by `ultralytics_yolo` before its network fallback.

SHA-256:
`77a3ee3f41beefdf4cc54a194bbc3f0d0101c1cf32f8084caeb257c01c57b2e5`

## Android LiteRT

`yolo26n_w8a32.tflite` is the official W8A32 LiteRT export published with the
`yolo-flutter-app` v0.6.6 release:

https://github.com/ultralytics/yolo-flutter-app/releases/tag/v0.6.6

The file is bundled at `assets/models/yolo26n_w8a32.tflite`, which the plugin
copies into application documents before its network fallback.

Exact size: `2875544` bytes

SHA-256:
`293074598c5f39b70d18ea9088bb0153ccc674310659d165d6d608f825b255ef`

Ultralytics distributes both models under its AGPL-3.0 open-source terms. See
the release repositories for the applicable license and commercial licensing
options.
