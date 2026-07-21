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
  String get modelSetupTitle => 'Set up your on-device AI';

  @override
  String get modelSetupDescription => 'Download the required models once. After setup, the assistant works offline.';

  @override
  String get modelSetupPrivacyMessage => 'Camera, audio, and conversations are not saved or uploaded.';

  @override
  String get modelSetupAssistantModelLabel => 'Assistant';

  @override
  String get modelSetupVisionModelLabel => 'Vision';

  @override
  String get modelSetupVoiceModelLabel => 'Voice';

  @override
  String get modelSetupListeningModelLabel => 'Listening';

  @override
  String modelSetupModelAccessibilityLabel(String title, String technicalName, String status) {
    return '$title. $technicalName. $status';
  }

  @override
  String modelSetupDownloadSummary(String downloadSize, String requiredStorage) {
    return '$downloadSize download · $requiredStorage free space required';
  }

  @override
  String get modelSetupOverallProgressLabel => 'Overall progress';

  @override
  String modelSetupPercentValue(int percent) {
    return '$percent%';
  }

  @override
  String get modelSetupModelWaitingStatus => 'Waiting';

  @override
  String get modelSetupModelPreparingStatus => 'Preparing…';

  @override
  String modelSetupModelDownloadingStatus(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get modelSetupModelVerifyingStatus => 'Verifying…';

  @override
  String get modelSetupModelVerifiedStatus => 'Verified';

  @override
  String get modelSetupModelFailureStatus => 'Needs attention';

  @override
  String get modelSetupCheckingAction => 'Checking device…';

  @override
  String get modelSetupDownloadAction => 'Download models';

  @override
  String get modelSetupCancelAction => 'Cancel download';

  @override
  String get modelSetupCancellingAction => 'Cancelling…';

  @override
  String get modelSetupVerifyingAction => 'Verifying…';

  @override
  String get modelSetupCompleteAction => 'Models ready';

  @override
  String get modelSetupOfflineMessage => 'Connect once to download the models.';

  @override
  String modelSetupStorageMessage(String requiredStorage, String availableStorage) {
    return 'Not enough storage. $requiredStorage is required; $availableStorage is available. Manage storage in Settings, then check again.';
  }

  @override
  String get modelSetupIntegrityMessage => 'A downloaded model could not be verified. Download it again.';

  @override
  String get modelSetupFailureMessage => 'The required models could not be prepared.';

  @override
  String get modelSetupTryAgainAction => 'Try again';

  @override
  String get modelSetupRetryAction => 'Retry';

  @override
  String get modelSetupDownloadAgainAction => 'Download again';

  @override
  String get modelSetupCheckAgainAction => 'Check again';

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
  String get handsFreeAgentTitle => 'Hands-free assistant';

  @override
  String get handsFreeAgentUnavailableMessage => 'Hands-free listening is paused while another task is active.';

  @override
  String get handsFreeAgentPreparingMessage => 'Preparing on-device speech recognition…';

  @override
  String handsFreeAgentDownloadingMessage(int percent) {
    return 'Downloading speech recognition: $percent%';
  }

  @override
  String get handsFreeAgentVerifyingMessage => 'Verifying on-device speech recognition…';

  @override
  String handsFreeAgentWatchingMessage(String wakePhrase) {
    return 'Say “$wakePhrase” to ask about the current scene.';
  }

  @override
  String get handsFreeAgentWakeDetectedMessage => 'Wake phrase detected. Ask your question.';

  @override
  String get handsFreeAgentListeningMessage => 'Listening for your question…';

  @override
  String get handsFreeAgentThinkingMessage => 'Thinking about your question…';

  @override
  String get handsFreeAgentSpeakingMessage => 'Speaking the answer…';

  @override
  String get handsFreeAgentSuspendedMessage => 'Hands-free listening is paused while the app is inactive.';

  @override
  String handsFreeAgentRecognizedSpeechLabel(String transcript) {
    return 'Heard: $transcript';
  }

  @override
  String handsFreeAgentQuestionLabel(String question) {
    return 'Question: $question';
  }

  @override
  String handsFreeAgentAnswerDraftLabel(String answer) {
    return 'Answering: $answer';
  }

  @override
  String get handsFreeAgentMicrophonePermissionFailureMessage =>
      'Microphone access is off. Allow it in Settings, then retry.';

  @override
  String get handsFreeAgentMicrophoneRestrictedFailureMessage =>
      'Microphone access is restricted by this device. Typed questions are still available.';

  @override
  String get handsFreeAgentModelNetworkFailureMessage =>
      'The speech model could not be downloaded. Check your connection and retry.';

  @override
  String get handsFreeAgentModelStorageFailureMessage =>
      'There is not enough free storage for on-device speech recognition.';

  @override
  String get handsFreeAgentModelIntegrityFailureMessage =>
      'The speech model did not pass verification. Retry the download.';

  @override
  String get handsFreeAgentModelUnavailableFailureMessage =>
      'On-device speech recognition could not start on this device.';

  @override
  String get handsFreeAgentModelFailureMessage => 'On-device speech recognition could not be prepared.';

  @override
  String handsFreeAgentEmptyQuestionFailureMessage(String wakePhrase) {
    return 'No question was heard. Say “$wakePhrase” and try again.';
  }

  @override
  String get handsFreeAgentRecognitionFailureMessage => 'Speech recognition stopped. Retry hands-free listening.';

  @override
  String get handsFreeAgentAnswerFailureMessage =>
      'The local assistant could not complete the spoken answer. Retry hands-free listening.';

  @override
  String get handsFreeAgentFailureMessage => 'Hands-free listening stopped. Retry to start it again.';

  @override
  String get handsFreeAgentRetryAction => 'Retry hands-free listening';

  @override
  String get observerTitle => 'Automatic observer';

  @override
  String get observerSceneTitle => 'Stable scene';

  @override
  String get observerModelReadyStatus => 'Local model ready';

  @override
  String get observerEmptySceneMessage => 'No stable objects are visible yet.';

  @override
  String get observerIntervalLabel => 'Observation interval';

  @override
  String get observerIntervalTenSecondsLabel => '10s';

  @override
  String get observerIntervalThirtySecondsLabel => '30s';

  @override
  String get observerIntervalOneMinuteLabel => '1m';

  @override
  String get observerIntervalTwoMinutesLabel => '2m';

  @override
  String get observerIntervalFiveMinutesLabel => '5m';

  @override
  String observerSceneObjectLabel(String label, int id, String region) {
    return '$label #$id · $region';
  }

  @override
  String get observerRegionUpperLeft => 'upper left';

  @override
  String get observerRegionUpperCenter => 'upper center';

  @override
  String get observerRegionUpperRight => 'upper right';

  @override
  String get observerRegionMiddleLeft => 'middle left';

  @override
  String get observerRegionCenter => 'center';

  @override
  String get observerRegionMiddleRight => 'middle right';

  @override
  String get observerRegionLowerLeft => 'lower left';

  @override
  String get observerRegionLowerCenter => 'lower center';

  @override
  String get observerRegionLowerRight => 'lower right';

  @override
  String observerRunningStatus(int seconds) {
    return 'Watching every $seconds seconds';
  }

  @override
  String get observerStoppedStatus => 'Automatic observation is stopped.';

  @override
  String get observerStartAction => 'Start observer';

  @override
  String get observerStopAction => 'Stop observer';

  @override
  String get observerTranscriptLabel => 'Automatic observation transcript';

  @override
  String get observerRoleLabel => 'Observer';

  @override
  String get observerThinkingMessage => 'Interpreting the latest scene…';

  @override
  String get observerGenerationFailureMessage =>
      'The observer could not comment on this scene. It will retry on the next interval.';

  @override
  String get observerMuteSpeechAction => 'Mute speech';

  @override
  String get observerUnmuteSpeechAction => 'Unmute speech';

  @override
  String get observerReplayCommentAction => 'Replay';

  @override
  String get observerStopSpeechAction => 'Stop';

  @override
  String get observerSpeechFailureMessage => 'Speech playback failed. Use the comment\'s speech control to recover.';

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

  @override
  String get settingsTabLabel => 'Settings';

  @override
  String get assistantStatusStarting => 'Starting';

  @override
  String get assistantStatusWatching => 'Watching';

  @override
  String get assistantStatusListening => 'Listening';

  @override
  String get assistantStatusThinking => 'Thinking';

  @override
  String get assistantStatusSpeaking => 'Speaking';

  @override
  String get assistantStatusPaused => 'Paused';

  @override
  String get assistantOnDeviceLabel => 'On device';

  @override
  String get assistantDiagnosticsPending => 'Performance pending';

  @override
  String assistantDiagnosticsLabel(int fps, int milliseconds) {
    return '$fps FPS · $milliseconds ms';
  }

  @override
  String get assistantNoCameraContext => 'No camera context';

  @override
  String get assistantSceneBuilding => 'Looking for stable objects';

  @override
  String assistantSceneObjectLabel(String label, String region) {
    return '$label · $region';
  }

  @override
  String get cameraRationaleTitle => 'Let Assistant see the scene';

  @override
  String get cameraRationaleMessage =>
      'Camera access lets the on-device assistant recognize objects around you. Frames stay on this device and are never saved.';

  @override
  String get continueAction => 'Continue';

  @override
  String get cameraPermissionDeniedInline => 'Camera access is off. Typed questions still work without a scene.';

  @override
  String get cameraPermissionRestrictedInline =>
      'Camera access is restricted by this device. Typed questions still work without a scene.';

  @override
  String get openSettingsAction => 'Open Settings';

  @override
  String assistantCardStateLabel(String status) {
    return 'ASSISTANT · $status';
  }

  @override
  String get assistantStatusNeedsAttention => 'Needs attention';

  @override
  String get assistantScenePromptPlaceholder => 'Ask about the detected scene...';

  @override
  String get assistantEmptyCardMessage => 'I’ll describe stable objects here. You can also ask a question.';

  @override
  String get currentSessionOpenAction => 'Open current session';

  @override
  String get currentSessionTitle => 'Current session';

  @override
  String get currentSessionClearsMessage => 'Clears when the app closes';

  @override
  String get currentSessionEmptyMessage => 'No comments or questions yet.';

  @override
  String get runtimeStartFailureMessage =>
      'The on-device Assistant could not start. Close and reopen the app to try again.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsObservationSection => 'Observation';

  @override
  String get settingsObservationFooter => 'Target cadence. Busy moments are skipped. Resets when the app closes.';

  @override
  String get settingsCommentInterval => 'Comment interval';

  @override
  String get settingsObservationStatus => 'Status';

  @override
  String get settingsPausedStatus => 'Paused while Settings is open';

  @override
  String get settingsAudioVoiceSection => 'Audio and voice';

  @override
  String get settingsSpeakResponses => 'Speak automatic responses';

  @override
  String get settingsHandsFreeListening => 'Hands-free listening';

  @override
  String get settingsWakePhrase => 'Wake phrase';

  @override
  String settingsWakePhraseValue(String wakePhrase) {
    return 'Say “$wakePhrase”';
  }

  @override
  String get settingsMicrophoneAccess => 'Microphone access';

  @override
  String get settingsPermissionDenied => 'Denied';

  @override
  String get settingsPermissionRestricted => 'Restricted by device policy';

  @override
  String get microphoneRationaleTitle => 'Enable hands-free listening';

  @override
  String get microphoneRationaleMessage =>
      'The microphone is used only while Assistant is open. Audio is processed on this device and is not saved.';

  @override
  String get enableMicrophoneAction => 'Enable microphone';

  @override
  String get settingsModelsSection => 'Models';

  @override
  String get settingsModelVerified => 'Verified';

  @override
  String get settingsModelNeedsAttention => 'Needs attention';

  @override
  String get settingsPrivacySection => 'Privacy';

  @override
  String get settingsPrivacySummary => 'Processing stays on this device.';

  @override
  String get privacyProcessingStatement => 'Processing stays on this device.';

  @override
  String get privacyMediaStatement => 'Photos, video, and audio are not saved.';

  @override
  String get privacyConversationStatement => 'Conversations are not saved between app launches.';

  @override
  String get privacyQwenStatement => 'Qwen receives detected object labels and approximate positions—not a photo.';

  @override
  String get privacyLifecycleStatement =>
      'The camera and microphone stop outside the Assistant tab and in the background.';

  @override
  String get settingsDiagnosticsSection => 'Diagnostics';

  @override
  String get settingsDiagnosticsAndLicenses => 'Diagnostics and licenses';

  @override
  String get settingsCurrentPerformance => 'Current performance';

  @override
  String get settingsThermalState => 'Thermal state';

  @override
  String get settingsThermalNominal => 'Nominal';

  @override
  String get settingsRuntimeVersions => 'Runtime versions';

  @override
  String get settingsRuntimeVersionsValue => 'YOLO · llama.cpp · Piper · ASR';

  @override
  String get settingsLicenses => 'Third-party licenses';

  @override
  String get settingsLicensesValue => 'Available in app bundle';

  @override
  String get settingsIntervalTenSeconds => '10 sec';

  @override
  String get settingsIntervalThirtySeconds => '30 sec';

  @override
  String get settingsIntervalOneMinute => '1 min';

  @override
  String get settingsIntervalTwoMinutes => '2 min';

  @override
  String get settingsIntervalFiveMinutes => '5 min';
}

/// The translations for English, as used in the United States (`en_US`).
class AppLocalizationsEnUs extends AppLocalizationsEn {
  AppLocalizationsEnUs() : super('en_US');
}
