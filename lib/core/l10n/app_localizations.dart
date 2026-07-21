import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('en', 'US')];

  /// Application title used by the operating system.
  ///
  /// In en, this message translates to:
  /// **'POV Agent'**
  String get appTitle;

  /// Large title on the mandatory model setup root screen.
  ///
  /// In en, this message translates to:
  /// **'Set up your on-device AI'**
  String get modelSetupTitle;

  /// Introductory copy explaining the one-time offline model setup.
  ///
  /// In en, this message translates to:
  /// **'Download the required models once. After setup, the assistant works offline.'**
  String get modelSetupDescription;

  /// Privacy assurance shown at the bottom of model setup.
  ///
  /// In en, this message translates to:
  /// **'Camera, audio, and conversations are not saved or uploaded.'**
  String get modelSetupPrivacyMessage;

  /// Friendly setup-row label for the local language model.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get modelSetupAssistantModelLabel;

  /// Friendly setup-row label for the local object detector.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get modelSetupVisionModelLabel;

  /// Friendly setup-row label for the local speech synthesizer.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get modelSetupVoiceModelLabel;

  /// Friendly setup-row label for local speech recognition.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get modelSetupListeningModelLabel;

  /// VoiceOver summary for one model setup row.
  ///
  /// In en, this message translates to:
  /// **'{title}. {technicalName}. {status}'**
  String modelSetupModelAccessibilityLabel(String title, String technicalName, String status);

  /// Model setup summary showing transfer size and required storage headroom.
  ///
  /// In en, this message translates to:
  /// **'{downloadSize} download · {requiredStorage} free space required'**
  String modelSetupDownloadSummary(String downloadSize, String requiredStorage);

  /// Label above the combined progress bar for the required model pack.
  ///
  /// In en, this message translates to:
  /// **'Overall progress'**
  String get modelSetupOverallProgressLabel;

  /// Percentage value used by model setup progress indicators.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String modelSetupPercentValue(int percent);

  /// Status for a required model that has not started downloading.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get modelSetupModelWaitingStatus;

  /// Status for a required model whose local cache is being inspected.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get modelSetupModelPreparingStatus;

  /// Status for a required model while bytes are being downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String modelSetupModelDownloadingStatus(int percent);

  /// Status for a required model while its local artifact is verified.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get modelSetupModelVerifyingStatus;

  /// Status for a required model whose pinned artifact passed verification.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get modelSetupModelVerifiedStatus;

  /// Status for a required model that failed preparation.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get modelSetupModelFailureStatus;

  /// Disabled primary action while model setup checks storage and receipts.
  ///
  /// In en, this message translates to:
  /// **'Checking device…'**
  String get modelSetupCheckingAction;

  /// Primary action that begins required model installation.
  ///
  /// In en, this message translates to:
  /// **'Download models'**
  String get modelSetupDownloadAction;

  /// Secondary action that stops unverified model transfers.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get modelSetupCancelAction;

  /// Disabled action label while model downloads are stopping.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get modelSetupCancellingAction;

  /// Disabled action label while the active model artifact is verified.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get modelSetupVerifyingAction;

  /// Disabled setup action shown briefly after every required model verifies.
  ///
  /// In en, this message translates to:
  /// **'Models ready'**
  String get modelSetupCompleteAction;

  /// Recovery message when required models cannot download without a connection.
  ///
  /// In en, this message translates to:
  /// **'Connect once to download the models.'**
  String get modelSetupOfflineMessage;

  /// iOS recovery message showing required and available capacity without an unsupported Settings deep link.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage. {requiredStorage} is required; {availableStorage} is available. Manage storage in Settings, then check again.'**
  String modelSetupStorageMessage(String requiredStorage, String availableStorage);

  /// Recovery message after a required model fails integrity verification.
  ///
  /// In en, this message translates to:
  /// **'A downloaded model could not be verified. Download it again.'**
  String get modelSetupIntegrityMessage;

  /// Fallback recovery message for a model setup failure.
  ///
  /// In en, this message translates to:
  /// **'The required models could not be prepared.'**
  String get modelSetupFailureMessage;

  /// Action that retries setup after an offline or preflight failure.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get modelSetupTryAgainAction;

  /// Action that retries a failed required-model preparation.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get modelSetupRetryAction;

  /// Action that downloads a required model again after integrity failure.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get modelSetupDownloadAgainAction;

  /// Action that rechecks available storage after the user frees space.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get modelSetupCheckAgainAction;

  /// Label and page title for the camera tab.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraTabLabel;

  /// Label and page title for the AI assistant tab.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistantTabLabel;

  /// Placeholder message centered on the camera tab.
  ///
  /// In en, this message translates to:
  /// **'Camera placeholder'**
  String get cameraPlaceholderTitle;

  /// Status shown before the router starts lazy assistant model preparation.
  ///
  /// In en, this message translates to:
  /// **'Open the Assistant tab to prepare the local model.'**
  String get assistantModelNotStartedMessage;

  /// Status shown while the assistant resolves its cache or loads the verified model.
  ///
  /// In en, this message translates to:
  /// **'Preparing the local Qwen model…'**
  String get assistantModelPreparingMessage;

  /// Progress status shown during the first assistant model download.
  ///
  /// In en, this message translates to:
  /// **'Downloading the Qwen model: {percent}%'**
  String assistantModelDownloadingMessage(int percent);

  /// Status shown while cached or downloaded assistant model bytes are verified.
  ///
  /// In en, this message translates to:
  /// **'Verifying the local Qwen model…'**
  String get assistantModelVerifyingMessage;

  /// Status shown after background lifecycle suspends model work.
  ///
  /// In en, this message translates to:
  /// **'The local assistant is paused while the app is inactive.'**
  String get assistantModelSuspendedMessage;

  /// Actionable assistant model failure shown for unavailable network transport.
  ///
  /// In en, this message translates to:
  /// **'The Qwen model could not be downloaded. Check your connection and retry.'**
  String get assistantModelNetworkFailureMessage;

  /// Actionable assistant model failure shown when the model volume lacks free space.
  ///
  /// In en, this message translates to:
  /// **'There is not enough free storage for the local Qwen model.'**
  String get assistantModelStorageFailureMessage;

  /// Actionable assistant model failure shown after size or checksum verification fails.
  ///
  /// In en, this message translates to:
  /// **'The downloaded Qwen model did not pass verification. Retry the download.'**
  String get assistantModelIntegrityFailureMessage;

  /// Actionable assistant model failure shown when native model services are unavailable.
  ///
  /// In en, this message translates to:
  /// **'The local Qwen model could not be loaded on this device.'**
  String get assistantModelUnavailableFailureMessage;

  /// Fallback assistant model preparation failure.
  ///
  /// In en, this message translates to:
  /// **'The local Qwen model could not be prepared.'**
  String get assistantModelFailureMessage;

  /// Title of the empty assistant conversation state after the model is ready.
  ///
  /// In en, this message translates to:
  /// **'Your on-device assistant is ready'**
  String get assistantReadyTitle;

  /// Body of the empty assistant conversation state.
  ///
  /// In en, this message translates to:
  /// **'Ask a question to begin a session-only conversation.'**
  String get assistantReadyMessage;

  /// Accessibility label for the scrollable session transcript.
  ///
  /// In en, this message translates to:
  /// **'Assistant conversation'**
  String get assistantConversationLabel;

  /// Compact role label displayed above a user message bubble.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get assistantUserRoleLabel;

  /// Compact role label displayed above a local assistant response bubble.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistantRoleLabel;

  /// Accessibility label for the manual assistant prompt field.
  ///
  /// In en, this message translates to:
  /// **'Message to the local assistant'**
  String get assistantPromptLabel;

  /// Placeholder shown in the multiline manual assistant prompt field.
  ///
  /// In en, this message translates to:
  /// **'Ask the local assistant…'**
  String get assistantPromptPlaceholder;

  /// Button and accessibility label for starting manual generation.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get assistantSendAction;

  /// Button and accessibility label for cancelling active manual generation.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get assistantStopAction;

  /// Placeholder shown in the response bubble before the first visible token arrives.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get assistantThinkingMessage;

  /// Recoverable failure shown under an uncommitted manual assistant turn.
  ///
  /// In en, this message translates to:
  /// **'The local assistant could not finish this answer.'**
  String get assistantGenerationFailureMessage;

  /// Button label for resubmitting the latest failed manual prompt.
  ///
  /// In en, this message translates to:
  /// **'Retry answer'**
  String get assistantRetryAnswerAction;

  /// Heading for the hands-free voice-agent status panel.
  ///
  /// In en, this message translates to:
  /// **'Hands-free assistant'**
  String get handsFreeAgentTitle;

  /// Status shown while foreground recognition is temporarily not armed.
  ///
  /// In en, this message translates to:
  /// **'Hands-free listening is paused while another task is active.'**
  String get handsFreeAgentUnavailableMessage;

  /// Status shown while the speech model cache or native recognizer is prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing on-device speech recognition…'**
  String get handsFreeAgentPreparingMessage;

  /// Progress status shown during the first speech-recognition model download.
  ///
  /// In en, this message translates to:
  /// **'Downloading speech recognition: {percent}%'**
  String handsFreeAgentDownloadingMessage(int percent);

  /// Status shown while cached or downloaded speech-model bytes are verified.
  ///
  /// In en, this message translates to:
  /// **'Verifying on-device speech recognition…'**
  String get handsFreeAgentVerifyingMessage;

  /// Status shown while recognition is armed and waiting for the wake phrase.
  ///
  /// In en, this message translates to:
  /// **'Say “{wakePhrase}” to ask about the current scene.'**
  String handsFreeAgentWatchingMessage(String wakePhrase);

  /// Status shown immediately after the configured wake phrase is recognized.
  ///
  /// In en, this message translates to:
  /// **'Wake phrase detected. Ask your question.'**
  String get handsFreeAgentWakeDetectedMessage;

  /// Status shown while the agent collects the spoken question.
  ///
  /// In en, this message translates to:
  /// **'Listening for your question…'**
  String get handsFreeAgentListeningMessage;

  /// Status shown while Qwen generates a hands-free answer.
  ///
  /// In en, this message translates to:
  /// **'Thinking about your question…'**
  String get handsFreeAgentThinkingMessage;

  /// Status shown while the committed hands-free answer is spoken.
  ///
  /// In en, this message translates to:
  /// **'Speaking the answer…'**
  String get handsFreeAgentSpeakingMessage;

  /// Status shown after lifecycle suspension releases foreground recognition.
  ///
  /// In en, this message translates to:
  /// **'Hands-free listening is paused while the app is inactive.'**
  String get handsFreeAgentSuspendedMessage;

  /// Live speech-recognition transcript shown during a hands-free question.
  ///
  /// In en, this message translates to:
  /// **'Heard: {transcript}'**
  String handsFreeAgentRecognizedSpeechLabel(String transcript);

  /// Recognized hands-free question shown during generation and speech.
  ///
  /// In en, this message translates to:
  /// **'Question: {question}'**
  String handsFreeAgentQuestionLabel(String question);

  /// Live uncommitted hands-free answer prefix shown during generation.
  ///
  /// In en, this message translates to:
  /// **'Answering: {answer}'**
  String handsFreeAgentAnswerDraftLabel(String answer);

  /// Actionable failure shown when hands-free microphone permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is off. Allow it in Settings, then retry.'**
  String get handsFreeAgentMicrophonePermissionFailureMessage;

  /// Explanation shown when device policy restricts microphone access and app settings cannot recover it.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is restricted by this device. Typed questions are still available.'**
  String get handsFreeAgentMicrophoneRestrictedFailureMessage;

  /// Actionable speech-model failure shown for unavailable network transport.
  ///
  /// In en, this message translates to:
  /// **'The speech model could not be downloaded. Check your connection and retry.'**
  String get handsFreeAgentModelNetworkFailureMessage;

  /// Actionable speech-model failure shown when its volume lacks free space.
  ///
  /// In en, this message translates to:
  /// **'There is not enough free storage for on-device speech recognition.'**
  String get handsFreeAgentModelStorageFailureMessage;

  /// Actionable speech-model failure shown after size or checksum verification fails.
  ///
  /// In en, this message translates to:
  /// **'The speech model did not pass verification. Retry the download.'**
  String get handsFreeAgentModelIntegrityFailureMessage;

  /// Actionable speech-model failure shown when native recognition services are unavailable.
  ///
  /// In en, this message translates to:
  /// **'On-device speech recognition could not start on this device.'**
  String get handsFreeAgentModelUnavailableFailureMessage;

  /// Fallback speech-model preparation failure.
  ///
  /// In en, this message translates to:
  /// **'On-device speech recognition could not be prepared.'**
  String get handsFreeAgentModelFailureMessage;

  /// Recoverable failure shown after a wake phrase with no spoken question.
  ///
  /// In en, this message translates to:
  /// **'No question was heard. Say “{wakePhrase}” and try again.'**
  String handsFreeAgentEmptyQuestionFailureMessage(String wakePhrase);

  /// Recoverable failure shown when microphone capture or recognition stops unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition stopped. Retry hands-free listening.'**
  String get handsFreeAgentRecognitionFailureMessage;

  /// Recoverable failure shown when generation or speech cannot complete a voice turn.
  ///
  /// In en, this message translates to:
  /// **'The local assistant could not complete the spoken answer. Retry hands-free listening.'**
  String get handsFreeAgentAnswerFailureMessage;

  /// Fallback recoverable hands-free failure.
  ///
  /// In en, this message translates to:
  /// **'Hands-free listening stopped. Retry to start it again.'**
  String get handsFreeAgentFailureMessage;

  /// Button label for retrying hands-free model, permission, or recognition setup.
  ///
  /// In en, this message translates to:
  /// **'Retry hands-free listening'**
  String get handsFreeAgentRetryAction;

  /// Heading for the continuous scene observer controls and transcript.
  ///
  /// In en, this message translates to:
  /// **'Automatic observer'**
  String get observerTitle;

  /// Heading above the latest stable scene objects.
  ///
  /// In en, this message translates to:
  /// **'Stable scene'**
  String get observerSceneTitle;

  /// Compact model status shown while observer generation is available.
  ///
  /// In en, this message translates to:
  /// **'Local model ready'**
  String get observerModelReadyStatus;

  /// Message shown while the stable scene contains no objects.
  ///
  /// In en, this message translates to:
  /// **'No stable objects are visible yet.'**
  String get observerEmptySceneMessage;

  /// Accessibility label for the session-only interval selector.
  ///
  /// In en, this message translates to:
  /// **'Observation interval'**
  String get observerIntervalLabel;

  /// Compact label for a ten-second observer interval.
  ///
  /// In en, this message translates to:
  /// **'10s'**
  String get observerIntervalTenSecondsLabel;

  /// Compact label for a thirty-second observer interval.
  ///
  /// In en, this message translates to:
  /// **'30s'**
  String get observerIntervalThirtySecondsLabel;

  /// Compact label for a one-minute observer interval.
  ///
  /// In en, this message translates to:
  /// **'1m'**
  String get observerIntervalOneMinuteLabel;

  /// Compact label for a two-minute observer interval.
  ///
  /// In en, this message translates to:
  /// **'2m'**
  String get observerIntervalTwoMinutesLabel;

  /// Compact label for a five-minute observer interval.
  ///
  /// In en, this message translates to:
  /// **'5m'**
  String get observerIntervalFiveMinutesLabel;

  /// Stable scene object label with session ID and grid region.
  ///
  /// In en, this message translates to:
  /// **'{label} #{id} · {region}'**
  String observerSceneObjectLabel(String label, int id, String region);

  /// Name of the upper-left scene grid region.
  ///
  /// In en, this message translates to:
  /// **'upper left'**
  String get observerRegionUpperLeft;

  /// Name of the upper-center scene grid region.
  ///
  /// In en, this message translates to:
  /// **'upper center'**
  String get observerRegionUpperCenter;

  /// Name of the upper-right scene grid region.
  ///
  /// In en, this message translates to:
  /// **'upper right'**
  String get observerRegionUpperRight;

  /// Name of the middle-left scene grid region.
  ///
  /// In en, this message translates to:
  /// **'middle left'**
  String get observerRegionMiddleLeft;

  /// Name of the center scene grid region.
  ///
  /// In en, this message translates to:
  /// **'center'**
  String get observerRegionCenter;

  /// Name of the middle-right scene grid region.
  ///
  /// In en, this message translates to:
  /// **'middle right'**
  String get observerRegionMiddleRight;

  /// Name of the lower-left scene grid region.
  ///
  /// In en, this message translates to:
  /// **'lower left'**
  String get observerRegionLowerLeft;

  /// Name of the lower-center scene grid region.
  ///
  /// In en, this message translates to:
  /// **'lower center'**
  String get observerRegionLowerCenter;

  /// Name of the lower-right scene grid region.
  ///
  /// In en, this message translates to:
  /// **'lower right'**
  String get observerRegionLowerRight;

  /// Status shown while periodic scene comments are enabled.
  ///
  /// In en, this message translates to:
  /// **'Watching every {seconds} seconds'**
  String observerRunningStatus(int seconds);

  /// Status shown while the automatic observer timer is disabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic observation is stopped.'**
  String get observerStoppedStatus;

  /// Button label for enabling periodic scene comments.
  ///
  /// In en, this message translates to:
  /// **'Start observer'**
  String get observerStartAction;

  /// Button label for disabling periodic comments and cancelling active observer generation.
  ///
  /// In en, this message translates to:
  /// **'Stop observer'**
  String get observerStopAction;

  /// Accessibility label for session-only automatic comments.
  ///
  /// In en, this message translates to:
  /// **'Automatic observation transcript'**
  String get observerTranscriptLabel;

  /// Role label displayed above automatic scene comments.
  ///
  /// In en, this message translates to:
  /// **'Observer'**
  String get observerRoleLabel;

  /// Placeholder shown before automatic comment text begins streaming.
  ///
  /// In en, this message translates to:
  /// **'Interpreting the latest scene…'**
  String get observerThinkingMessage;

  /// Recoverable automatic generation failure shown until the next timer attempt.
  ///
  /// In en, this message translates to:
  /// **'The observer could not comment on this scene. It will retry on the next interval.'**
  String get observerGenerationFailureMessage;

  /// Accessibility label for muting automatic observer speech without stopping text observation.
  ///
  /// In en, this message translates to:
  /// **'Mute speech'**
  String get observerMuteSpeechAction;

  /// Accessibility label for restoring automatic observer speech for future comments.
  ///
  /// In en, this message translates to:
  /// **'Unmute speech'**
  String get observerUnmuteSpeechAction;

  /// Button label for speaking a completed observer comment again.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get observerReplayCommentAction;

  /// Button label for stopping the observer comment currently being spoken.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get observerStopSpeechAction;

  /// Recoverable system speech failure shown without removing the completed text comment.
  ///
  /// In en, this message translates to:
  /// **'Speech playback failed. Use the comment\'s speech control to recover.'**
  String get observerSpeechFailureMessage;

  /// Message shown when the user has manually disabled the camera.
  ///
  /// In en, this message translates to:
  /// **'Camera is off.'**
  String get cameraDisabledMessage;

  /// Button and accessibility label for enabling the camera.
  ///
  /// In en, this message translates to:
  /// **'Enable camera'**
  String get cameraEnableAction;

  /// Accessibility label for disabling the camera.
  ///
  /// In en, this message translates to:
  /// **'Disable camera'**
  String get cameraDisableAction;

  /// Accessibility label for switching between front and rear cameras.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get cameraSwitchAction;

  /// Guidance shown when camera permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is disabled. Allow camera access in Settings, then retry.'**
  String get cameraPermissionDeniedMessage;

  /// Message shown when the device has no supported camera.
  ///
  /// In en, this message translates to:
  /// **'No supported camera is available on this device.'**
  String get cameraUnavailableMessage;

  /// Fallback message shown when camera startup fails.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be started.'**
  String get cameraFailureMessage;

  /// Message shown while the native camera session starts or switches lenses.
  ///
  /// In en, this message translates to:
  /// **'Starting the camera…'**
  String get cameraStartingMessage;

  /// Message shown while the YOLO model is resolved from cache or prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing the YOLO model…'**
  String get cameraModelPreparingMessage;

  /// Progress message shown during the first YOLO model download.
  ///
  /// In en, this message translates to:
  /// **'Downloading the YOLO model: {percent}%'**
  String cameraModelDownloadingMessage(int percent);

  /// Fallback message shown when the YOLO model cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'The YOLO model could not be prepared.'**
  String get cameraModelFailureMessage;

  /// Message shown when the first YOLO model download fails because of connectivity.
  ///
  /// In en, this message translates to:
  /// **'The YOLO model could not be downloaded. Check your connection and retry.'**
  String get cameraModelNetworkFailureMessage;

  /// Message shown when a loaded YOLO model cannot analyze an observation frame.
  ///
  /// In en, this message translates to:
  /// **'The frame could not be analyzed.'**
  String get cameraObservationFailureMessage;

  /// Compact live inference frame-rate diagnostic.
  ///
  /// In en, this message translates to:
  /// **'FPS {fps}'**
  String cameraFpsLabel(String fps);

  /// Compact live model inference-time diagnostic.
  ///
  /// In en, this message translates to:
  /// **'Inference {milliseconds} ms'**
  String cameraInferenceLabel(String milliseconds);

  /// Generic scaffolded feature page title.
  ///
  /// In en, this message translates to:
  /// **'{featureName}'**
  String featurePageTitle(String featureName);

  /// Message shown when a load-once list has no items.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get emptyStateMessage;

  /// Button label for retrying a failed operation.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// Label for the Settings root destination.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTabLabel;

  /// Operational badge shown while Assistant resources are starting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get assistantStatusStarting;

  /// Operational badge shown while camera observation is active and idle.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get assistantStatusWatching;

  /// Operational badge shown while hands-free input collects a question.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get assistantStatusListening;

  /// Operational badge shown while the local language model generates.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get assistantStatusThinking;

  /// Operational badge shown while an Assistant response is spoken.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get assistantStatusSpeaking;

  /// Operational badge shown after the user pauses Assistant.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get assistantStatusPaused;

  /// Privacy-preserving runtime label beside the Assistant status badge.
  ///
  /// In en, this message translates to:
  /// **'On device'**
  String get assistantOnDeviceLabel;

  /// Compact diagnostics placeholder before the first camera sample.
  ///
  /// In en, this message translates to:
  /// **'Performance pending'**
  String get assistantDiagnosticsPending;

  /// Compact camera frame-rate and inference-duration diagnostic.
  ///
  /// In en, this message translates to:
  /// **'{fps} FPS · {milliseconds} ms'**
  String assistantDiagnosticsLabel(int fps, int milliseconds);

  /// Persistent Assistant state when camera context is unavailable.
  ///
  /// In en, this message translates to:
  /// **'No camera context'**
  String get assistantNoCameraContext;

  /// Stable-scene chip shown while no object has stabilized yet.
  ///
  /// In en, this message translates to:
  /// **'Looking for stable objects'**
  String get assistantSceneBuilding;

  /// Compact Assistant camera-overlay chip for a stable object and its coarse position.
  ///
  /// In en, this message translates to:
  /// **'{label} · {region}'**
  String assistantSceneObjectLabel(String label, String region);

  /// Heading in the contextual camera-permission explanation.
  ///
  /// In en, this message translates to:
  /// **'Let Assistant see the scene'**
  String get cameraRationaleTitle;

  /// Privacy explanation shown before the native camera permission request.
  ///
  /// In en, this message translates to:
  /// **'Camera access lets the on-device assistant recognize objects around you. Frames stay on this device and are never saved.'**
  String get cameraRationaleMessage;

  /// Action that proceeds from a contextual explanation to a system request.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// Inline iOS camera-denial explanation that preserves manual chat.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Typed questions still work without a scene.'**
  String get cameraPermissionDeniedInline;

  /// Inline explanation when device policy prevents camera access and app settings cannot recover it.
  ///
  /// In en, this message translates to:
  /// **'Camera access is restricted by this device. Typed questions still work without a scene.'**
  String get cameraPermissionRestrictedInline;

  /// Action that opens platform application settings for permission recovery.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettingsAction;

  /// Compact state label above the latest Assistant response.
  ///
  /// In en, this message translates to:
  /// **'ASSISTANT · {status}'**
  String assistantCardStateLabel(String status);

  /// Operational badge shown while a recoverable Assistant or camera failure needs user action.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get assistantStatusNeedsAttention;

  /// Placeholder in the camera-first manual question composer.
  ///
  /// In en, this message translates to:
  /// **'Ask about the detected scene...'**
  String get assistantScenePromptPlaceholder;

  /// Assistant card copy before the first response in a runtime session.
  ///
  /// In en, this message translates to:
  /// **'I’ll describe stable objects here. You can also ask a question.'**
  String get assistantEmptyCardMessage;

  /// Accessibility action for opening the session transcript sheet.
  ///
  /// In en, this message translates to:
  /// **'Open current session'**
  String get currentSessionOpenAction;

  /// Title of the in-memory session transcript sheet.
  ///
  /// In en, this message translates to:
  /// **'Current session'**
  String get currentSessionTitle;

  /// Privacy line beneath the current-session sheet title.
  ///
  /// In en, this message translates to:
  /// **'Clears when the app closes'**
  String get currentSessionClearsMessage;

  /// Empty state inside the current-session transcript sheet.
  ///
  /// In en, this message translates to:
  /// **'No comments or questions yet.'**
  String get currentSessionEmptyMessage;

  /// Blocking message shown when the process runtime cannot start after setup.
  ///
  /// In en, this message translates to:
  /// **'The on-device Assistant could not start. Close and reopen the app to try again.'**
  String get runtimeStartFailureMessage;

  /// Large title of the Settings destination.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Heading for automatic observation preferences.
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get settingsObservationSection;

  /// Explanatory footer below observation preferences.
  ///
  /// In en, this message translates to:
  /// **'Target cadence. Busy moments are skipped. Resets when the app closes.'**
  String get settingsObservationFooter;

  /// Disclosure row for selecting the automatic comment cadence.
  ///
  /// In en, this message translates to:
  /// **'Comment interval'**
  String get settingsCommentInterval;

  /// Label for the observation status row in Settings.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get settingsObservationStatus;

  /// Observation status displayed while Settings owns the foreground.
  ///
  /// In en, this message translates to:
  /// **'Paused while Settings is open'**
  String get settingsPausedStatus;

  /// Heading for speech and hands-free preferences.
  ///
  /// In en, this message translates to:
  /// **'Audio and voice'**
  String get settingsAudioVoiceSection;

  /// Session switch controlling automatic and voice response speech.
  ///
  /// In en, this message translates to:
  /// **'Speak automatic responses'**
  String get settingsSpeakResponses;

  /// Session switch controlling wake-phrase microphone input.
  ///
  /// In en, this message translates to:
  /// **'Hands-free listening'**
  String get settingsHandsFreeListening;

  /// Label for the configured hands-free wake phrase.
  ///
  /// In en, this message translates to:
  /// **'Wake phrase'**
  String get settingsWakePhrase;

  /// Displayed instruction for the hands-free wake phrase.
  ///
  /// In en, this message translates to:
  /// **'Say “{wakePhrase}”'**
  String settingsWakePhraseValue(String wakePhrase);

  /// Permission-recovery row shown after hands-free microphone denial.
  ///
  /// In en, this message translates to:
  /// **'Microphone access'**
  String get settingsMicrophoneAccess;

  /// Compact permission state shown when system access is denied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get settingsPermissionDenied;

  /// Compact permission state shown when app settings cannot recover restricted microphone access.
  ///
  /// In en, this message translates to:
  /// **'Restricted by device policy'**
  String get settingsPermissionRestricted;

  /// Heading in the contextual microphone-permission explanation.
  ///
  /// In en, this message translates to:
  /// **'Enable hands-free listening'**
  String get microphoneRationaleTitle;

  /// Privacy explanation shown before the native microphone permission request.
  ///
  /// In en, this message translates to:
  /// **'The microphone is used only while Assistant is open. Audio is processed on this device and is not saved.'**
  String get microphoneRationaleMessage;

  /// Action that proceeds to the native microphone permission request.
  ///
  /// In en, this message translates to:
  /// **'Enable microphone'**
  String get enableMicrophoneAction;

  /// Heading for verified on-device model rows.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsModelsSection;

  /// Status of a model that passed local integrity verification.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get settingsModelVerified;

  /// Status of a required model that is not currently verified.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get settingsModelNeedsAttention;

  /// Heading for local-processing and retention information.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacySection;

  /// Disclosure row summarizing the product privacy boundary.
  ///
  /// In en, this message translates to:
  /// **'Processing stays on this device.'**
  String get settingsPrivacySummary;

  /// Privacy detail describing the local processing boundary.
  ///
  /// In en, this message translates to:
  /// **'Processing stays on this device.'**
  String get privacyProcessingStatement;

  /// Privacy detail describing media retention.
  ///
  /// In en, this message translates to:
  /// **'Photos, video, and audio are not saved.'**
  String get privacyMediaStatement;

  /// Privacy detail describing conversation retention.
  ///
  /// In en, this message translates to:
  /// **'Conversations are not saved between app launches.'**
  String get privacyConversationStatement;

  /// Privacy detail describing the scene data given to Qwen.
  ///
  /// In en, this message translates to:
  /// **'Qwen receives detected object labels and approximate positions—not a photo.'**
  String get privacyQwenStatement;

  /// Privacy detail describing destination and lifecycle resource ownership.
  ///
  /// In en, this message translates to:
  /// **'The camera and microphone stop outside the Assistant tab and in the background.'**
  String get privacyLifecycleStatement;

  /// Heading for performance and license information.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnosticsSection;

  /// Disclosure row and detail title for diagnostics and third-party licenses.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics and licenses'**
  String get settingsDiagnosticsAndLicenses;

  /// Label for the latest camera inference performance sample.
  ///
  /// In en, this message translates to:
  /// **'Current performance'**
  String get settingsCurrentPerformance;

  /// Label for current device thermal status.
  ///
  /// In en, this message translates to:
  /// **'Thermal state'**
  String get settingsThermalState;

  /// Value shown when no thermal degradation is active.
  ///
  /// In en, this message translates to:
  /// **'Nominal'**
  String get settingsThermalNominal;

  /// Label for local inference runtime version information.
  ///
  /// In en, this message translates to:
  /// **'Runtime versions'**
  String get settingsRuntimeVersions;

  /// Compact list of local runtime families used by the app.
  ///
  /// In en, this message translates to:
  /// **'YOLO · llama.cpp · Piper · ASR'**
  String get settingsRuntimeVersionsValue;

  /// Label for third-party model and runtime license information.
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get settingsLicenses;

  /// Compact value describing bundled third-party license notices.
  ///
  /// In en, this message translates to:
  /// **'Available in app bundle'**
  String get settingsLicensesValue;

  /// Full Settings label for a ten-second comment interval.
  ///
  /// In en, this message translates to:
  /// **'10 sec'**
  String get settingsIntervalTenSeconds;

  /// Full Settings label for a thirty-second comment interval.
  ///
  /// In en, this message translates to:
  /// **'30 sec'**
  String get settingsIntervalThirtySeconds;

  /// Full Settings label for a one-minute comment interval.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get settingsIntervalOneMinute;

  /// Full Settings label for a two-minute comment interval.
  ///
  /// In en, this message translates to:
  /// **'2 min'**
  String get settingsIntervalTwoMinutes;

  /// Full Settings label for a five-minute comment interval.
  ///
  /// In en, this message translates to:
  /// **'5 min'**
  String get settingsIntervalFiveMinutes;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'US':
            return AppLocalizationsEnUs();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
