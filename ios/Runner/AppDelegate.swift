import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var recordedVideoFrameChannel: RecordedVideoFrameChannel?
  private var modelDiskCapacityChannel: ModelDiskCapacityChannel?
  private let backgroundModelDownloads = BackgroundModelDownloadCoordinator.shared
  private var backgroundModelDownloadChannel: BackgroundModelDownloadChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    backgroundModelDownloads.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard backgroundModelDownloads.handlesBackgroundSession(identifier: identifier) else {
      super.application(
        application,
        handleEventsForBackgroundURLSession: identifier,
        completionHandler: completionHandler
      )
      return
    }
    backgroundModelDownloads.setBackgroundEventsCompletion(completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    recordedVideoFrameChannel = RecordedVideoFrameChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    modelDiskCapacityChannel = ModelDiskCapacityChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    backgroundModelDownloadChannel = BackgroundModelDownloadChannel(
      messenger: engineBridge.applicationRegistrar.messenger(),
      coordinator: backgroundModelDownloads
    )
  }
}
