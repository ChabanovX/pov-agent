import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
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
  final ObserverState state;

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
    final downloading = state.modelStatus == ObserverModelStatus.downloading;
    final loading = switch (state.modelStatus) {
      ObserverModelStatus.loading || ObserverModelStatus.downloading || ObserverModelStatus.verifying => true,
      _ => false,
    };

    return Padding(
      padding: spacing.topMd,
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
                    color: state.modelStatus == ObserverModelStatus.failure ? colors.danger : colors.primary,
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
                if (state.modelStatus == ObserverModelStatus.failure)
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
    );
  }

  String _messageFor(AppLocalizations localizations) {
    return switch (state.modelStatus) {
      ObserverModelStatus.idle => localizations.assistantModelNotStartedMessage,
      ObserverModelStatus.loading => localizations.assistantModelPreparingMessage,
      ObserverModelStatus.downloading => localizations.assistantModelDownloadingMessage(
        ((state.modelDownloadProgress ?? 0) * 100).round(),
      ),
      ObserverModelStatus.verifying => localizations.assistantModelVerifyingMessage,
      ObserverModelStatus.suspended => localizations.assistantModelSuspendedMessage,
      ObserverModelStatus.failure => _failureMessage(localizations),
      ObserverModelStatus.ready => localizations.assistantReadyTitle,
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

IconData _iconFor(ObserverModelStatus status) {
  return switch (status) {
    ObserverModelStatus.failure => CupertinoIcons.exclamationmark_triangle,
    ObserverModelStatus.suspended => CupertinoIcons.pause_circle,
    ObserverModelStatus.idle => CupertinoIcons.chat_bubble_2,
    _ => CupertinoIcons.sparkles,
  };
}
