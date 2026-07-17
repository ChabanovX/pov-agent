// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Camera Assistant';

  @override
  String get cameraTabLabel => 'Camera';

  @override
  String get assistantTabLabel => 'Assistant';

  @override
  String get cameraPlaceholderTitle => 'Camera placeholder';

  @override
  String get assistantPlaceholderTitle => 'Assistant placeholder';

  @override
  String get cameraDisabledMessage => 'Camera is off.';

  @override
  String get cameraEnableAction => 'Enable camera';

  @override
  String get cameraDisableAction => 'Disable camera';

  @override
  String get cameraSwitchAction => 'Switch camera';

  @override
  String get cameraPermissionDeniedMessage => 'Camera access is disabled. Allow camera access in Settings, then retry.';

  @override
  String get cameraUnavailableMessage => 'No supported camera is available on this device.';

  @override
  String get cameraFailureMessage => 'The camera could not be started.';

  @override
  String get cameraStartingMessage => 'Starting the camera…';

  @override
  String get cameraModelPreparingMessage => 'Preparing the YOLO model…';

  @override
  String cameraModelDownloadingMessage(int percent) {
    return 'Downloading the YOLO model: $percent%';
  }

  @override
  String get cameraModelFailureMessage => 'The YOLO model could not be prepared.';

  @override
  String get cameraModelNetworkFailureMessage =>
      'The YOLO model could not be downloaded. Check your connection and retry.';

  @override
  String get cameraObservationFailureMessage => 'The frame could not be analyzed.';

  @override
  String cameraFpsLabel(String fps) {
    return 'FPS $fps';
  }

  @override
  String cameraInferenceLabel(String milliseconds) {
    return 'Inference $milliseconds ms';
  }

  @override
  String featurePageTitle(String featureName) {
    return '$featureName';
  }

  @override
  String get emptyStateMessage => 'Nothing here yet.';

  @override
  String get retryAction => 'Retry';
}
