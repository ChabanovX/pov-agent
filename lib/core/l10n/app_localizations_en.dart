// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'POV Agent';

  @override
  String get cameraTabLabel => 'Camera';

  @override
  String get assistantTabLabel => 'Assistant';

  @override
  String get cameraPlaceholderTitle => 'Camera placeholder';

  @override
  String get assistantModelNotStartedMessage => 'Open the Assistant tab to prepare the local model.';

  @override
  String get assistantModelPreparingMessage => 'Preparing the local Qwen model…';

  @override
  String assistantModelDownloadingMessage(int percent) {
    return 'Downloading the Qwen model: $percent%';
  }

  @override
  String get assistantModelVerifyingMessage => 'Verifying the local Qwen model…';

  @override
  String get assistantModelSuspendedMessage => 'The local assistant is paused while the app is inactive.';

  @override
  String get assistantModelNetworkFailureMessage =>
      'The Qwen model could not be downloaded. Check your connection and retry.';

  @override
  String get assistantModelStorageFailureMessage => 'There is not enough free storage for the local Qwen model.';

  @override
  String get assistantModelIntegrityFailureMessage =>
      'The downloaded Qwen model did not pass verification. Retry the download.';

  @override
  String get assistantModelUnavailableFailureMessage => 'The local Qwen model could not be loaded on this device.';

  @override
  String get assistantModelFailureMessage => 'The local Qwen model could not be prepared.';

  @override
  String get assistantReadyTitle => 'Your on-device assistant is ready';

  @override
  String get assistantReadyMessage => 'Ask a question to begin a session-only conversation.';

  @override
  String get assistantConversationLabel => 'Assistant conversation';

  @override
  String get assistantUserRoleLabel => 'You';

  @override
  String get assistantRoleLabel => 'Assistant';

  @override
  String get assistantPromptLabel => 'Message to the local assistant';

  @override
  String get assistantPromptPlaceholder => 'Ask the local assistant…';

  @override
  String get assistantSendAction => 'Send';

  @override
  String get assistantStopAction => 'Stop';

  @override
  String get assistantThinkingMessage => 'Thinking…';

  @override
  String get assistantGenerationFailureMessage => 'The local assistant could not finish this answer.';

  @override
  String get assistantRetryAnswerAction => 'Retry answer';

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
