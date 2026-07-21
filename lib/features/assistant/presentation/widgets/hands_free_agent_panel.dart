import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Projects hands-free model, listening, generation, and speech state.
final class HandsFreeAgentPanel extends StatelessWidget {
  /// Creates a hands-free status surface from [state].
  const HandsFreeAgentPanel({
    required this.state,
    required this.onRetry,
    super.key,
  });

  /// The observer state projected into hands-free status and live text.
  final ObserverState state;

  /// Retries a recoverable model, permission, or recognition failure.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const shadows = AppShadows.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final presentation = _presentationFor(localizations);
    final transcript = _transcriptFor(localizations);
    final question = _questionFor(localizations);
    final answerDraft = _answerDraftFor(localizations);

    return Semantics(
      key: handsFreeAgentPanelKey,
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: radius.lg,
          boxShadow: shadows.level1,
        ),
        child: Padding(
          padding: spacing.section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (presentation.busy)
                    const CupertinoActivityIndicator()
                  else
                    Icon(
                      presentation.icon,
                      color: presentation.failure ? colors.danger : colors.primary,
                    ),
                  Expanded(
                    child: Padding(
                      padding: spacing.startSm,
                      child: Text(
                        localizations.handsFreeAgentTitle,
                        style: typography.title.copyWith(color: colors.onSurface),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: spacing.topSm,
                child: Text(
                  presentation.message,
                  style: typography.body.copyWith(
                    color: presentation.failure ? colors.danger : colors.muted,
                  ),
                ),
              ),
              if (state.asrModelStatus == ObserverModelStatus.downloading)
                Padding(
                  padding: spacing.topMd,
                  child: _HandsFreeDownloadProgress(
                    progress: state.asrModelDownloadProgress ?? 0,
                  ),
                ),
              if (transcript != null)
                Padding(
                  padding: spacing.topSm,
                  child: Text(
                    transcript,
                    style: typography.label.copyWith(color: colors.onSurface),
                  ),
                ),
              if (question != null)
                Padding(
                  padding: spacing.topSm,
                  child: Text(
                    question,
                    style: typography.label.copyWith(color: colors.onSurface),
                  ),
                ),
              if (answerDraft != null)
                Padding(
                  padding: spacing.topSm,
                  child: Text(
                    answerDraft,
                    style: typography.label.copyWith(color: colors.onSurface),
                  ),
                ),
              if (presentation.failure)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: spacing.topMd,
                    child: CupertinoButton.filled(
                      key: handsFreeAgentRetryButtonKey,
                      padding: spacing.compactControl,
                      onPressed: onRetry,
                      child: Text(localizations.handsFreeAgentRetryAction),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _HandsFreePresentation _presentationFor(
    AppLocalizations localizations,
  ) {
    return switch (state.voicePhase) {
      VoiceAgentPhase.unavailable => _HandsFreePresentation(
        message: localizations.handsFreeAgentUnavailableMessage,
        icon: CupertinoIcons.mic_slash,
      ),
      VoiceAgentPhase.preparing => _HandsFreePresentation(
        message: _preparationMessage(localizations),
        icon: CupertinoIcons.waveform,
        busy: true,
      ),
      VoiceAgentPhase.watching => _HandsFreePresentation(
        message: localizations.handsFreeAgentWatchingMessage(
          _displayWakePhrase,
        ),
        icon: CupertinoIcons.mic,
      ),
      VoiceAgentPhase.wakeDetected => _HandsFreePresentation(
        message: localizations.handsFreeAgentWakeDetectedMessage,
        icon: CupertinoIcons.mic_fill,
      ),
      VoiceAgentPhase.listening => _HandsFreePresentation(
        message: localizations.handsFreeAgentListeningMessage,
        icon: CupertinoIcons.mic_fill,
      ),
      VoiceAgentPhase.thinking => _HandsFreePresentation(
        message: localizations.handsFreeAgentThinkingMessage,
        icon: CupertinoIcons.sparkles,
        busy: true,
      ),
      VoiceAgentPhase.speaking => _HandsFreePresentation(
        message: localizations.handsFreeAgentSpeakingMessage,
        icon: CupertinoIcons.speaker_2_fill,
      ),
      VoiceAgentPhase.failure => _HandsFreePresentation(
        message: _failureMessage(localizations),
        icon: CupertinoIcons.exclamationmark_circle,
        failure: true,
      ),
      VoiceAgentPhase.suspended => _HandsFreePresentation(
        message: localizations.handsFreeAgentSuspendedMessage,
        icon: CupertinoIcons.pause_circle,
      ),
    };
  }

  String _preparationMessage(AppLocalizations localizations) {
    return switch (state.asrModelStatus) {
      ObserverModelStatus.downloading => localizations.handsFreeAgentDownloadingMessage(
        ((state.asrModelDownloadProgress ?? 0) * 100).round(),
      ),
      ObserverModelStatus.verifying => localizations.handsFreeAgentVerifyingMessage,
      _ => localizations.handsFreeAgentPreparingMessage,
    };
  }

  String _failureMessage(AppLocalizations localizations) {
    final failure = state.asrModelFailure ?? state.voiceFailure;
    if (failure is PermissionDeniedFailure || failure?.code.startsWith('microphone_permission_') == true) {
      return localizations.handsFreeAgentMicrophonePermissionFailureMessage;
    }
    if (state.asrModelFailure != null) {
      if (failure?.code == 'model_insufficient_storage') {
        return localizations.handsFreeAgentModelStorageFailureMessage;
      }
      if (failure?.code == 'model_integrity') {
        return localizations.handsFreeAgentModelIntegrityFailureMessage;
      }
      return switch (failure) {
        NetworkFailure() => localizations.handsFreeAgentModelNetworkFailureMessage,
        DeviceUnavailableFailure() => localizations.handsFreeAgentModelUnavailableFailureMessage,
        _ => localizations.handsFreeAgentModelFailureMessage,
      };
    }
    if (failure?.code == 'voice_question_empty' || failure?.code == 'voice_question_silence_timeout') {
      return localizations.handsFreeAgentEmptyQuestionFailureMessage(
        _displayWakePhrase,
      );
    }
    if (_isAnswerFailure(failure?.code)) {
      return localizations.handsFreeAgentAnswerFailureMessage;
    }
    if (failure is DeviceUnavailableFailure || failure?.code.startsWith('asr_') == true) {
      return localizations.handsFreeAgentRecognitionFailureMessage;
    }
    return localizations.handsFreeAgentFailureMessage;
  }

  String get _displayWakePhrase {
    final phrase = state.wakePhrase.trim();
    if (phrase.isEmpty) return phrase;
    return '${phrase[0].toUpperCase()}${phrase.substring(1)}';
  }

  String? _transcriptFor(AppLocalizations localizations) {
    if (state.voicePhase != VoiceAgentPhase.wakeDetected && state.voicePhase != VoiceAgentPhase.listening) {
      return null;
    }
    final transcript = state.voiceQuestionDraft.trim();
    return transcript.isEmpty ? null : localizations.handsFreeAgentRecognizedSpeechLabel(transcript);
  }

  String? _questionFor(AppLocalizations localizations) {
    if (state.voicePhase != VoiceAgentPhase.thinking && state.voicePhase != VoiceAgentPhase.speaking) {
      return null;
    }
    final question = state.voiceQuestionDraft.trim();
    return question.isEmpty ? null : localizations.handsFreeAgentQuestionLabel(question);
  }

  String? _answerDraftFor(AppLocalizations localizations) {
    if (state.voicePhase != VoiceAgentPhase.thinking) return null;
    final answer = state.voiceAnswerDraft.trim();
    return answer.isEmpty ? null : localizations.handsFreeAgentAnswerDraftLabel(answer);
  }
}

final class _HandsFreeDownloadProgress extends StatelessWidget {
  const _HandsFreeDownloadProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final normalized = progress.clamp(0, 1).toDouble();

    return Semantics(
      value: '${(normalized * 100).round()}%',
      child: ClipRRect(
        borderRadius: radius.sm,
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(
            width: sizes.progressTrackWidth,
            height: spacing.sm,
          ),
          child: ColoredBox(
            color: colors.muted.withValues(alpha: 0.2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: normalized,
                child: ColoredBox(color: colors.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _HandsFreePresentation {
  const _HandsFreePresentation({
    required this.message,
    required this.icon,
    this.busy = false,
    this.failure = false,
  });

  final String message;
  final IconData icon;
  final bool busy;
  final bool failure;
}

bool _isAnswerFailure(String? code) {
  return code?.startsWith('voice_assistant_') == true ||
      code?.startsWith('voice_answer_') == true ||
      code?.startsWith('assistant_generation') == true ||
      code == 'assistant_empty_response';
}
