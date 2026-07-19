import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Projects a non-ready assistant model phase into actionable status UI.
final class AssistantModelStatusView extends StatelessWidget {
  /// Creates model status content for [state].
  const AssistantModelStatusView({
    required this.state,
    required this.onRetry,
    super.key,
  });

  /// The model state rendered by this status surface.
  final AssistantState state;

  /// Retries a recoverable model preparation failure.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const shadows = AppShadows.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final message = _messageFor(localizations);
    final downloading = state.modelStatus == AssistantModelStatus.downloading;
    final loading = switch (state.modelStatus) {
      AssistantModelStatus.loading || AssistantModelStatus.downloading || AssistantModelStatus.verifying => true,
      _ => false,
    };

    return Center(
      child: SingleChildScrollView(
        padding: spacing.page,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: radius.lg,
            boxShadow: shadows.level1,
          ),
          child: Padding(
            padding: spacing.insetXl,
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const CupertinoActivityIndicator()
                  else
                    Icon(
                      _iconFor(state.modelStatus),
                      color: state.modelStatus == AssistantModelStatus.failure ? colors.danger : colors.primary,
                      size: spacing.xl,
                    ),
                  Padding(
                    padding: spacing.topMd,
                    child: Text(
                      message,
                      style: typography.body.copyWith(color: colors.onSurface),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (downloading)
                    Padding(
                      padding: spacing.topLg,
                      child: _DownloadProgress(
                        progress: state.modelDownloadProgress ?? 0,
                      ),
                    ),
                  if (state.modelStatus == AssistantModelStatus.failure)
                    Padding(
                      padding: spacing.topLg,
                      child: CupertinoButton.filled(
                        key: assistantModelRetryButtonKey,
                        onPressed: onRetry,
                        child: Text(localizations.retryAction),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _messageFor(AppLocalizations localizations) {
    return switch (state.modelStatus) {
      AssistantModelStatus.idle => localizations.assistantModelNotStartedMessage,
      AssistantModelStatus.loading => localizations.assistantModelPreparingMessage,
      AssistantModelStatus.downloading => localizations.assistantModelDownloadingMessage(
        ((state.modelDownloadProgress ?? 0) * 100).round(),
      ),
      AssistantModelStatus.verifying => localizations.assistantModelVerifyingMessage,
      AssistantModelStatus.suspended => localizations.assistantModelSuspendedMessage,
      AssistantModelStatus.failure => _failureMessage(localizations),
      AssistantModelStatus.ready => localizations.assistantReadyTitle,
    };
  }

  String _failureMessage(AppLocalizations localizations) {
    final failure = state.modelFailure;
    if (failure?.code == 'model_insufficient_storage') {
      return localizations.assistantModelStorageFailureMessage;
    }
    if (failure?.code == 'model_integrity') {
      return localizations.assistantModelIntegrityFailureMessage;
    }
    return switch (failure) {
      NetworkFailure() => localizations.assistantModelNetworkFailureMessage,
      DeviceUnavailableFailure() => localizations.assistantModelUnavailableFailureMessage,
      _ => localizations.assistantModelFailureMessage,
    };
  }
}

final class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

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

IconData _iconFor(AssistantModelStatus status) {
  return switch (status) {
    AssistantModelStatus.failure => CupertinoIcons.exclamationmark_triangle,
    AssistantModelStatus.suspended => CupertinoIcons.pause_circle,
    AssistantModelStatus.idle => CupertinoIcons.chat_bubble_2,
    _ => CupertinoIcons.sparkles,
  };
}
