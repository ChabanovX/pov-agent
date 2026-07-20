import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';

/// Renders automatic-observer scene, cadence, controls, and transcript.
final class ObserverSessionPanel extends StatelessWidget {
  /// Creates an observer panel from process-owned [state].
  const ObserverSessionPanel({
    required this.state,
    required this.onIntervalSelected,
    required this.onStart,
    required this.onStop,
    super.key,
  });

  /// The observer state projected into the panel.
  final ObserverState state;

  /// Replaces the session-only automatic cadence.
  final ValueChanged<ObserverInterval> onIntervalSelected;

  /// Enables automatic observation.
  final VoidCallback onStart;

  /// Disables automatic observation and cancels its active generation.
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const shadows = AppShadows.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return DecoratedBox(
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
                Icon(CupertinoIcons.eye, color: colors.primary),
                Expanded(
                  child: Padding(
                    padding: spacing.startSm,
                    child: Text(
                      localizations.observerTitle,
                      style: typography.title.copyWith(color: colors.onSurface),
                    ),
                  ),
                ),
                if (state.modelStatus == ObserverModelStatus.ready)
                  Text(
                    localizations.observerModelReadyStatus,
                    style: typography.label.copyWith(color: colors.primary),
                  ),
              ],
            ),
            Padding(
              padding: spacing.topLg,
              child: Text(
                localizations.observerSceneTitle,
                style: typography.label.copyWith(color: colors.onSurface),
              ),
            ),
            Padding(
              key: observerSceneKey,
              padding: spacing.topSm,
              child: _SceneObjects(state: state),
            ),
            Padding(
              padding: spacing.topLg,
              child: Semantics(
                label: localizations.observerIntervalLabel,
                child: CupertinoSlidingSegmentedControl<ObserverInterval>(
                  key: observerIntervalControlKey,
                  groupValue: state.interval,
                  children: {
                    for (final interval in ObserverInterval.values)
                      interval: Padding(
                        padding: spacing.insetSm,
                        child: Text(_intervalLabel(localizations, interval)),
                      ),
                  },
                  onValueChanged: (interval) {
                    if (interval != null) onIntervalSelected(interval);
                  },
                ),
              ),
            ),
            Padding(
              padding: spacing.topMd,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      state.observationEnabled
                          ? localizations.observerRunningStatus(
                              state.interval.seconds,
                            )
                          : localizations.observerStoppedStatus,
                      style: typography.body.copyWith(color: colors.muted),
                    ),
                  ),
                  CupertinoButton(
                    key: observerToggleButtonKey,
                    padding: spacing.compactControl,
                    color: state.observationEnabled ? null : colors.primary,
                    onPressed: state.started
                        ? state.observationEnabled
                              ? onStop
                              : onStart
                        : null,
                    child: Text(
                      state.observationEnabled ? localizations.observerStopAction : localizations.observerStartAction,
                    ),
                  ),
                ],
              ),
            ),
            if (state.comments.isNotEmpty ||
                state.activeGeneration == ObserverGenerationKind.automatic ||
                state.automaticFailure != null)
              Padding(
                padding: spacing.topLg,
                child: Semantics(
                  key: observerTranscriptKey,
                  container: true,
                  liveRegion: true,
                  label: localizations.observerTranscriptLabel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final comment in state.comments) _ObserverCommentBubble(comment: comment.text),
                      if (state.activeGeneration == ObserverGenerationKind.automatic)
                        _AutomaticDraft(text: state.automaticDraft),
                      if (state.automaticFailure != null)
                        _AutomaticFailure(
                          message: localizations.observerGenerationFailureMessage,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _SceneObjects extends StatelessWidget {
  const _SceneObjects({required this.state});

  final ObserverState state;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    if (state.scene.isEmpty) {
      return Text(
        AppLocalizations.of(context).observerEmptySceneMessage,
        style: typography.body.copyWith(color: colors.muted),
      );
    }

    return Wrap(
      spacing: spacing.sm,
      runSpacing: spacing.sm,
      children: [
        for (final object in state.scene.objects)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: radius.md,
            ),
            child: Padding(
              padding: spacing.insetSm,
              child: Text(
                localizations.observerSceneObjectLabel(
                  object.label,
                  object.id,
                  _regionLabel(localizations, object.region),
                ),
                style: typography.label.copyWith(color: colors.onSurface),
              ),
            ),
          ),
      ],
    );
  }
}

final class _ObserverCommentBubble extends StatelessWidget {
  const _ObserverCommentBubble({required this.comment});

  final String comment;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: spacing.bottomMd,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: radius.md,
        ),
        child: Padding(
          padding: spacing.section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.observerRoleLabel,
                style: typography.label.copyWith(color: colors.primary),
              ),
              Padding(
                padding: spacing.topXs,
                child: Text(
                  comment,
                  style: typography.body.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AutomaticDraft extends StatelessWidget {
  const _AutomaticDraft({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CupertinoActivityIndicator(),
        Expanded(
          child: Padding(
            padding: spacing.startSm,
            child: Text(
              text.isEmpty ? localizations.observerThinkingMessage : text,
              style: typography.body.copyWith(color: colors.muted),
            ),
          ),
        ),
      ],
    );
  }
}

final class _AutomaticFailure extends StatelessWidget {
  const _AutomaticFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.exclamationmark_circle, color: colors.danger),
        Expanded(
          child: Padding(
            padding: spacing.startSm,
            child: Text(
              message,
              style: typography.body.copyWith(color: colors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

String _intervalLabel(
  AppLocalizations localizations,
  ObserverInterval interval,
) {
  return switch (interval) {
    ObserverInterval.tenSeconds => localizations.observerIntervalTenSecondsLabel,
    ObserverInterval.thirtySeconds => localizations.observerIntervalThirtySecondsLabel,
    ObserverInterval.oneMinute => localizations.observerIntervalOneMinuteLabel,
    ObserverInterval.twoMinutes => localizations.observerIntervalTwoMinutesLabel,
    ObserverInterval.fiveMinutes => localizations.observerIntervalFiveMinutesLabel,
  };
}

String _regionLabel(AppLocalizations localizations, SceneRegion region) {
  return switch (region) {
    SceneRegion.leftTop => localizations.observerRegionUpperLeft,
    SceneRegion.top => localizations.observerRegionUpperCenter,
    SceneRegion.rightTop => localizations.observerRegionUpperRight,
    SceneRegion.left => localizations.observerRegionMiddleLeft,
    SceneRegion.center => localizations.observerRegionCenter,
    SceneRegion.right => localizations.observerRegionMiddleRight,
    SceneRegion.leftBottom => localizations.observerRegionLowerLeft,
    SceneRegion.bottom => localizations.observerRegionLowerCenter,
    SceneRegion.rightBottom => localizations.observerRegionLowerRight,
  };
}
