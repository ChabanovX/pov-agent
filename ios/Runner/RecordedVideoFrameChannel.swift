import AVFoundation
import CoreImage
import Flutter
import UIKit

private let recordedVideoChannelName = "pov_agent/recorded_video"

/// Pull-based decoder for the bundled debug video.
///
/// AVAssetReader state is confined to one serial queue. Dart requests another
/// frame only after YOLO finishes the previous one, so decoded frames are never
/// buffered across the platform boundary.
final class RecordedVideoFrameChannel {
  private let channel: FlutterMethodChannel
  private let decodeQueue = DispatchQueue(
    label: "pov_agent.recorded_video_decoder",
    qos: .userInitiated
  )
  private let imageContext = CIContext(options: [.cacheIntermediates: false])

  private var asset: AVURLAsset?
  private var videoTrack: AVAssetTrack?
  private var reader: AVAssetReader?
  private var trackOutput: AVAssetReaderTrackOutput?
  private var preferredTransform = CGAffineTransform.identity
  private var frameNumber: Int64 = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: recordedVideoChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "VIDEO_READER_UNAVAILABLE",
            message: "The recorded video decoder has already been released.",
            details: nil
          )
        )
        return
      }
      self.handle(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      guard
        let arguments = call.arguments as? [String: Any],
        let assetPath = arguments["assetPath"] as? String,
        !assetPath.isEmpty
      else {
        result(
          FlutterError(
            code: "VIDEO_INVALID_ARGUMENTS",
            message: "open requires a non-empty assetPath.",
            details: nil
          )
        )
        return
      }
      perform(result) { try self.open(assetPath: assetPath) }
    case "nextFrame":
      perform(result) { try self.nextFrame() }
    case "close":
      perform(result) {
        self.closeReader()
        return nil
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func perform(
    _ result: @escaping FlutterResult,
    operation: @escaping () throws -> Any?
  ) {
    decodeQueue.async {
      do {
        let value = try operation()
        DispatchQueue.main.async { result(value) }
      } catch let failure as RecordedVideoChannelFailure {
        DispatchQueue.main.async { result(failure.flutterError) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "VIDEO_READER_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func open(assetPath: String) throws -> [String: Any] {
    closeReader()

    let lookupKey = FlutterDartProject.lookupKey(forAsset: assetPath)
    guard let path = Bundle.main.path(forResource: lookupKey, ofType: nil) else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_ASSET_NOT_FOUND",
        message: "Bundled video asset was not found: \(assetPath)"
      )
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_NO_TRACK",
        message: "The bundled asset contains no video track."
      )
    }

    let preferredTransform = track.preferredTransform
    let transformedSize = track.naturalSize.applying(preferredTransform)
    let width = Int(abs(transformedSize.width).rounded())
    let height = Int(abs(transformedSize.height).rounded())
    guard width > 0, height > 0 else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_NO_TRACK",
        message: "The video track reports invalid dimensions."
      )
    }

    let durationSeconds = CMTimeGetSeconds(asset.duration)
    let durationMicroseconds: Int64
    if durationSeconds.isFinite, durationSeconds > 0 {
      durationMicroseconds = Int64((durationSeconds * 1_000_000).rounded())
    } else {
      durationMicroseconds = 0
    }

    self.asset = asset
    videoTrack = track
    self.preferredTransform = preferredTransform
    frameNumber = 0
    do {
      try startReader()
    } catch {
      closeReader()
      throw error
    }

    return [
      "width": width,
      "height": height,
      "durationMicroseconds": durationMicroseconds,
    ]
  }

  private func nextFrame() throws -> [String: Any] {
    guard reader != nil, trackOutput != nil else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_READER_FAILED",
        message: "The recorded video must be opened before requesting frames."
      )
    }

    var sampleBuffer = trackOutput?.copyNextSampleBuffer()
    if sampleBuffer == nil {
      switch reader?.status {
      case .completed:
        try startReader()
        sampleBuffer = trackOutput?.copyNextSampleBuffer()
      case .failed:
        throw RecordedVideoChannelFailure(
          code: "VIDEO_READER_FAILED",
          message: reader?.error?.localizedDescription ?? "Video reader failed."
        )
      case .cancelled:
        throw RecordedVideoChannelFailure(
          code: "VIDEO_READER_FAILED",
          message: "Video reader was cancelled."
        )
      default:
        break
      }
    }

    guard
      let sampleBuffer,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_EMPTY",
        message: "The recorded video produced no decodable frames."
      )
    }

    let jpegData = try autoreleasepool {
      var image = CIImage(cvPixelBuffer: pixelBuffer)
      if !preferredTransform.isIdentity {
        image = image.transformed(by: preferredTransform)
      }
      let transformedExtent = image.extent.integral
      image = image.transformed(
        by: CGAffineTransform(
          translationX: -transformedExtent.origin.x,
          y: -transformedExtent.origin.y
        )
      )
      guard
        let cgImage = imageContext.createCGImage(image, from: image.extent),
        let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
      else {
        throw RecordedVideoChannelFailure(
          code: "VIDEO_FRAME_DECODE_FAILED",
          message: "A decoded video frame could not be encoded as JPEG."
        )
      }
      return data
    }

    frameNumber += 1
    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let presentationSeconds = CMTimeGetSeconds(presentationTime)
    let presentationTimeMicroseconds =
      presentationSeconds.isFinite && presentationSeconds > 0
      ? Int64((presentationSeconds * 1_000_000).rounded())
      : 0

    return [
      "bytes": FlutterStandardTypedData(bytes: jpegData),
      "frameNumber": frameNumber,
      "presentationTimeMicroseconds": presentationTimeMicroseconds,
    ]
  }

  private func startReader() throws {
    guard let asset, let videoTrack else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_READER_FAILED",
        message: "Video reader has no configured asset."
      )
    }

    reader?.cancelReading()
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: videoTrack,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_READER_FAILED",
        message: "AVAssetReader rejected the configured video output."
      )
    }
    reader.add(output)
    guard reader.startReading() else {
      throw RecordedVideoChannelFailure(
        code: "VIDEO_READER_FAILED",
        message: reader.error?.localizedDescription ?? "Video reader did not start."
      )
    }
    self.reader = reader
    trackOutput = output
  }

  private func closeReader() {
    reader?.cancelReading()
    reader = nil
    trackOutput = nil
    videoTrack = nil
    asset = nil
    preferredTransform = .identity
    frameNumber = 0
  }
}

private struct RecordedVideoChannelFailure: Error {
  let code: String
  let message: String

  var flutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
