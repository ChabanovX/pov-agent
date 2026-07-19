import Flutter
import Foundation

private let modelStorageChannelName = "pov_agent/model_storage"

/// Reports free bytes for the filesystem that owns the model cache.
final class ModelDiskCapacityChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: modelStorageChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "availableBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let directoryPath = arguments["directoryPath"] as? String,
        !directoryPath.isEmpty
      else {
        result(
          FlutterError(
            code: "MODEL_STORAGE_INVALID_ARGUMENTS",
            message: "availableBytes requires a non-empty directoryPath.",
            details: nil
          )
        )
        return
      }

      do {
        let attributes = try FileManager.default.attributesOfFileSystem(
          forPath: directoryPath
        )
        guard
          let freeSize = attributes[.systemFreeSize] as? NSNumber,
          freeSize.int64Value >= 0
        else {
          result(
            FlutterError(
              code: "MODEL_STORAGE_INVALID_RESPONSE",
              message: "The cache volume did not report a valid free byte count.",
              details: nil
            )
          )
          return
        }
        result(freeSize.int64Value)
      } catch {
        result(
          FlutterError(
            code: "MODEL_STORAGE_LOOKUP_FAILED",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
