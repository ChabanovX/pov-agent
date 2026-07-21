/// Wall-clock budgets shared by opt-in Assistant integration lanes.
///
/// These are test contracts rather than visual animation timings, so they stay
/// independent from the application's design-system duration tokens.
abstract final class AssistantAcceptanceDurations {
  static const modelPreparation = Duration(minutes: 15);
  static const modelReload = Duration(minutes: 5);
  static const Duration liveQuestion = modelReload;
  static const runtimeStart = Duration(minutes: 5);
  static const generation = Duration(minutes: 10);
  static const shortComment = Duration(seconds: 10);
  static const streamSettlement = Duration(seconds: 10);
  static const cancellation = Duration(seconds: 10);
  static const stateTransition = Duration(seconds: 30);
  static const runtimeClose = Duration(seconds: 30);
  static const dependencyReset = Duration(seconds: 10);
  static const widgetDetach = Duration(seconds: 10);
  static const subscriptionCancel = Duration(seconds: 10);
  static const soak = Duration(minutes: 10);
  static const soakProgress = Duration(minutes: 1);
  static const poll = Duration(milliseconds: 120);
  static const hardwareScenario = Duration(minutes: 55);
  static const smokeScenario = Duration(minutes: 40);
  static const offlineScenario = Duration(minutes: 20);
  static const observerScenario = Duration(minutes: 30);
  static const observerLiveSmokeScenario = Duration(minutes: 40);
  static const observerLiveScene = Duration(minutes: 3);
  static const observerTickWait = Duration(seconds: 20);
  static const observerStopSilence = Duration(seconds: 12);

  /// Polls short native ownership transitions that can complete between UI
  /// frame pumps on fast simulator hosts.
  static const nativeProbePoll = Duration(milliseconds: 20);
}
