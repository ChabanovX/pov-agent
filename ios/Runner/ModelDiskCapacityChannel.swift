import Flutter
import Foundation

private let modelStorageChannelName = "pov_agent/model_storage"

/// Resolves no-backup model storage and reports its filesystem capacity.
final class ModelDiskCapacityChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: modelStorageChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "MODEL_STORAGE_CHANNEL_RELEASED",
            message: "The model storage channel is no longer available.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "resolveDirectory":
        self.resolveDirectory(result: result)
      case "availableBytes":
        self.reportAvailableBytes(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func resolveDirectory(result: @escaping FlutterResult) {
    do {
      let supportDirectory = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      var modelDirectory = supportDirectory.appendingPathComponent(
        "models",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: modelDirectory,
        withIntermediateDirectories: true
      )
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      try modelDirectory.setResourceValues(resourceValues)
      result(modelDirectory.path)
    } catch {
      result(
        FlutterError(
          code: "MODEL_STORAGE_DIRECTORY_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func reportAvailableBytes(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
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

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
