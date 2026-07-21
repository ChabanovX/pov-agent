import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';

/// The camera-first Assistant destination composed above camera and assistant
/// feature contracts at the application boundary.
final class AssistantCameraPage extends StatefulWidget {
  /// Creates the Assistant destination with an app-selected camera surface.
  const AssistantCameraPage({
    required this.surfaceBuilder,
    super.key,
  });

  /// Builds the selected live or recorded observation surface.
  final WidgetBuilder surfaceBuilder;

  @override
  State<AssistantCameraPage> createState() => _AssistantCameraPageState();
}

final class _AssistantCameraPageState extends State<AssistantCameraPage> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocus = FocusNode();
  String? _submittedPrompt;

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    return BlocListener<ObserverBloc, ObserverState>(
      listenWhen: (previous, current) {
        return previous.activeGeneration != current.activeGeneration ||
            previous.manualDraftPrompt != current.manualDraftPrompt;
      },
      listener: (_, state) => _clearAcceptedPrompt(state),
      child: BlocBuilder<CameraBloc, CameraState>(
        builder: (context, cameraState) {
          return BlocBuilder<ObserverBloc, ObserverState>(
            builder: (context, observerState) {
              return ColoredBox(
                color: AppColors.dark.background,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CameraStage(
                      state: cameraState,
                      surfaceBuilder: widget.surfaceBuilder,
                    ),
                    const _CameraScrims(),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: spacing.cameraOverlay,
                        child: Column(
                          children: [
                            _TopStatusBar(
                              cameraState: cameraState,
                              observerState: observerState,
                              onToggleLens: () {
                                context.read<CameraBloc>().add(
                                  const CameraLensToggleRequested(),
                                );
                              },
                              onPauseChanged: (paused) {
                                _setPaused(context, paused: paused);
                              },
                            ),
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: spacing.insetSm,
                                  child: !cameraState.activationRequested
                                      ? _CameraPermissionRationale(
                                          onContinue: () {
                                            context.read<CameraBloc>().add(
                                              const CameraEnableRequested(),
                                            );
                                          },
                                        )
                                      : cameraState.cameraFailure != null
                                      ? _CameraUnavailableCard(
                                          failure: cameraState.cameraFailure!,
                                          onRetry: () {
                                            context.read<CameraBloc>().add(
                                              const CameraRetryRequested(),
                                            );
                                          },
                                          onOpenSettings: () {
                                            context.read<CameraBloc>().add(
                                              const CameraPermissionSettingsRequested(),
                                            );
                                          },
                                        )
                                      : cameraState.modelFailure != null || cameraState.observationFailure != null
                                      ? _CameraPipelineFailureCard(
                                          state: cameraState,
                                          onRetry: () {
                                            context.read<CameraBloc>().add(
                                              const CameraRetryRequested(),
                                            );
                                          },
                                        )
                                      : cameraState.modelStatus == ObservationModelStatus.preparing ||
                                            cameraState.modelStatus == ObservationModelStatus.downloading
                                      ? _CameraPipelineLoadingCard(
                                          state: cameraState,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            _StableSceneStrip(
                              state: observerState,
                              hasCameraContext:
                                  cameraState.status == CameraStatus.enabled && cameraState.cameraFailure == null,
                              onOpenScene: () {
                                _showStableScene(context, observerState);
                              },
                            ),
                            _SpacingGap(padding: spacing.topComponent),
                            _AssistantOutputCard(
                              state: observerState,
                              status: _statusFor(
                                cameraState,
                                observerState,
                              ),
                              onOpenSession: () {
                                _showCurrentSession(context, observerState);
                              },
                              onStop: () => _stopActiveWork(context, observerState),
                              onReplay: observerState.speechMuted || !_hasReplayableResponse(observerState)
                                  ? null
                                  : () {
                                      _replayLatestResponse(
                                        context,
                                        observerState,
                                      );
                                    },
                              onMuteChanged: (muted) {
                                context.read<ObserverBloc>().add(
                                  ObserverSpeechMutedChanged(muted: muted),
                                );
                              },
                              onModelRetry: () {
                                context.read<ObserverBloc>().add(
                                  const ObserverModelRetryRequested(),
                                );
                              },
                              onAnswerRetry: () {
                                context.read<ObserverBloc>().add(
                                  const ObserverAnswerRetryRequested(),
                                );
                              },
                              onVoiceRetry: () {
                                context.read<ObserverBloc>().add(
                                  const ObserverVoiceRetryRequested(),
                                );
                              },
                            ),
                            _SpacingGap(padding: spacing.topComponent),
                            _QuestionComposer(
                              controller: _promptController,
                              focusNode: _promptFocus,
                              enabled: observerState.canSubmit,
                              submitting: observerState.activeGeneration == ObserverGenerationKind.manual,
                              onSubmit: _submitPrompt,
                              onStop: () {
                                context.read<ObserverBloc>().add(
                                  const ObserverManualGenerationCancelled(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _submitPrompt() {
    final bloc = context.read<ObserverBloc>();
    final prompt = _promptController.text.trim();
    if (!bloc.state.canSubmit || prompt.isEmpty) return;
    _submittedPrompt = prompt;
    _promptFocus.unfocus();
    bloc.add(ObserverPromptSubmitted(prompt));
  }

  void _clearAcceptedPrompt(ObserverState state) {
    final submittedPrompt = _submittedPrompt;
    if (submittedPrompt == null ||
        state.activeGeneration != ObserverGenerationKind.manual ||
        state.manualDraftPrompt != submittedPrompt) {
      return;
    }
    _submittedPrompt = null;
    if (_promptController.text.trim() == submittedPrompt) {
      _promptController.clear();
    }
  }
}

final class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.state,
    required this.surfaceBuilder,
  });

  final CameraState state;
  final WidgetBuilder surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const sizes = AppSizes.regular;
    final canRender =
        state.activationRequested &&
        state.requestedEnabled &&
        state.surfaceMounted &&
        state.status == CameraStatus.enabled &&
        state.cameraFailure == null;
    if (canRender) return surfaceBuilder(context);

    final localizations = AppLocalizations.of(context);
    final isPaused = state.activationRequested && !state.requestedEnabled;
    return Semantics(
      label: isPaused ? localizations.assistantStatusPaused : localizations.assistantNoCameraContext,
      child: ColoredBox(
        color: AppColors.dark.background,
        child: Center(
          child: Icon(
            isPaused ? CupertinoIcons.pause_fill : CupertinoIcons.camera,
            size: sizes.heroIcon,
            color: colors.muted.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

final class _CameraScrims extends StatelessWidget {
  const _CameraScrims();

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.cameraScrimTop,
              colors.cameraScrimClear,
              colors.cameraScrimMiddle,
              colors.cameraScrimBottom,
            ],
            stops: const [0, 0.24, 0.58, 1],
          ),
        ),
      ),
    );
  }
}

enum _AssistantVisualStatus {
  starting,
  watching,
  listening,
  thinking,
  speaking,
  paused,
  needsAttention,
}

_AssistantVisualStatus _statusFor(
  CameraState camera,
  ObserverState observer,
) {
  if (camera.activationRequested && !camera.requestedEnabled) {
    return _AssistantVisualStatus.paused;
  }
  if (camera.failure != null || observer.modelFailure != null) {
    return _AssistantVisualStatus.needsAttention;
  }
  if (observer.voicePhase == VoiceAgentPhase.wakeDetected || observer.voicePhase == VoiceAgentPhase.listening) {
    return _AssistantVisualStatus.listening;
  }
  if (observer.isGenerating) return _AssistantVisualStatus.thinking;
  if (observer.isSpeaking) return _AssistantVisualStatus.speaking;
  if (camera.status == CameraStatus.enabled &&
      camera.modelStatus == ObservationModelStatus.ready &&
      camera.failure == null &&
      observer.modelStatus == ObserverModelStatus.ready) {
    return _AssistantVisualStatus.watching;
  }
  return _AssistantVisualStatus.starting;
}

final class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.cameraState,
    required this.observerState,
    required this.onToggleLens,
    required this.onPauseChanged,
  });

  final CameraState cameraState;
  final ObserverState observerState;
  final VoidCallback onToggleLens;
  final ValueChanged<bool> onPauseChanged;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    final status = _statusFor(cameraState, observerState);
    final localizations = AppLocalizations.of(context);
    final (label, color, icon) = switch (status) {
      _AssistantVisualStatus.starting => (
        localizations.assistantStatusStarting,
        AppColors.dark.muted,
        CupertinoIcons.hourglass,
      ),
      _AssistantVisualStatus.watching => (
        localizations.assistantStatusWatching,
        AppColors.dark.success,
        CupertinoIcons.eye_fill,
      ),
      _AssistantVisualStatus.listening => (
        localizations.assistantStatusListening,
        AppColors.dark.listening,
        CupertinoIcons.waveform,
      ),
      _AssistantVisualStatus.thinking => (
        localizations.assistantStatusThinking,
        AppColors.dark.listening,
        CupertinoIcons.sparkles,
      ),
      _AssistantVisualStatus.speaking => (
        localizations.assistantStatusSpeaking,
        AppColors.dark.warning,
        CupertinoIcons.speaker_2_fill,
      ),
      _AssistantVisualStatus.paused => (
        localizations.assistantStatusPaused,
        AppColors.dark.muted,
        CupertinoIcons.pause_fill,
      ),
      _AssistantVisualStatus.needsAttention => (
        localizations.assistantStatusNeedsAttention,
        AppColors.dark.danger,
        CupertinoIcons.exclamationmark_triangle_fill,
      ),
    };
    final diagnostics = cameraState.diagnostics;
    final paused = status == _AssistantVisualStatus.paused;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(label: label, color: color, icon: icon),
        _SpacingGap(padding: spacing.startSm),
        Expanded(
          child: Padding(
            padding: spacing.topXs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: spacing.sm,
                      height: spacing.sm,
                      decoration: BoxDecoration(
                        color: AppColors.dark.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    _SpacingGap(padding: spacing.startXs),
                    Flexible(
                      child: Text(
                        localizations.assistantOnDeviceLabel,
                        style: AppTypography.regular.metadata.copyWith(
                          color: AppColors.dark.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  diagnostics == null
                      ? localizations.assistantDiagnosticsPending
                      : localizations.assistantDiagnosticsLabel(
                          diagnostics.framesPerSecond.round(),
                          diagnostics.inferenceTimeMs.round(),
                        ),
                  style: AppTypography.regular.status.copyWith(
                    color: AppColors.dark.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        _RoundIconButton(
          semanticLabel: localizations.cameraSwitchAction,
          icon: CupertinoIcons.camera_rotate,
          onPressed: cameraState.canToggleLens && !paused ? onToggleLens : null,
        ),
        _SpacingGap(padding: spacing.startSm),
        _RoundIconButton(
          semanticLabel: paused ? localizations.cameraEnableAction : localizations.cameraDisableAction,
          icon: paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
          onPressed: cameraState.activationRequested ? () => onPauseChanged(!paused) : null,
        ),
      ],
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return Semantics(
      label: label,
      child: Container(
        constraints: BoxConstraints(minHeight: sizes.statusBadgeHeight),
        padding: spacing.statusBadge,
        decoration: BoxDecoration(
          color: colors.overlayStrong,
          borderRadius: radius.full,
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: spacing.component, color: color),
            _SpacingGap(padding: spacing.startXs),
            Text(
              label,
              style: AppTypography.regular.status.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

final class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        minimumSize: Size.square(sizes.controlHeight),
        padding: EdgeInsets.zero,
        borderRadius: radius.full,
        color: colors.overlayStrong,
        disabledColor: colors.overlaySoft,
        onPressed: onPressed,
        child: Icon(icon, size: sizes.icon, color: colors.textPrimary),
      ),
    );
  }
}

final class _CameraPermissionRationale extends StatelessWidget {
  const _CameraPermissionRationale({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _CameraContextCard(
      icon: CupertinoIcons.lock_shield_fill,
      title: localizations.cameraRationaleTitle,
      message: localizations.cameraRationaleMessage,
      actionLabel: localizations.continueAction,
      onAction: onContinue,
    );
  }
}

final class _CameraUnavailableCard extends StatelessWidget {
  const _CameraUnavailableCard({
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final permissionDenied = failure is PermissionDeniedFailure;
    final restricted = failure.code == 'camera_permission_restricted';
    final canOpenSettings = permissionDenied && !restricted;
    return _CameraContextCard(
      icon: CupertinoIcons.camera,
      title: localizations.assistantNoCameraContext,
      message: restricted
          ? localizations.cameraPermissionRestrictedInline
          : permissionDenied
          ? localizations.cameraPermissionDeniedInline
          : localizations.cameraUnavailableMessage,
      actionLabel: canOpenSettings ? localizations.openSettingsAction : localizations.retryAction,
      onAction: canOpenSettings ? onOpenSettings : onRetry,
    );
  }
}

final class _CameraPipelineFailureCard extends StatelessWidget {
  const _CameraPipelineFailureCard({
    required this.state,
    required this.onRetry,
  });

  final CameraState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final modelFailure = state.modelFailure;
    final message = state.observationFailure != null
        ? localizations.cameraObservationFailureMessage
        : modelFailure is NetworkFailure
        ? localizations.cameraModelNetworkFailureMessage
        : localizations.cameraModelFailureMessage;
    return _CameraContextCard(
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      title: localizations.assistantStatusNeedsAttention,
      message: message,
      actionLabel: localizations.retryAction,
      onAction: onRetry,
    );
  }
}

final class _CameraPipelineLoadingCard extends StatelessWidget {
  const _CameraPipelineLoadingCard({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final downloading = state.modelStatus == ObservationModelStatus.downloading;
    final progress = state.modelDownloadProgress ?? 0;
    return _CameraContextCard(
      icon: CupertinoIcons.viewfinder,
      title: localizations.assistantStatusStarting,
      message: downloading
          ? localizations.cameraModelDownloadingMessage(
              (progress * 100).round(),
            )
          : localizations.cameraModelPreparingMessage,
      progress: downloading ? progress : null,
    );
  }
}

final class _CameraContextCard extends StatelessWidget {
  const _CameraContextCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return Container(
      constraints: BoxConstraints(maxWidth: sizes.cameraContextMaxWidth),
      padding: spacing.page,
      decoration: BoxDecoration(
        color: colors.overlayStrong,
        borderRadius: radius.card,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.textPrimary, size: sizes.sheetIcon),
          _SpacingGap(padding: spacing.topComponent),
          Text(
            title,
            style: AppTypography.regular.headline.copyWith(
              color: AppColors.dark.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          _SpacingGap(padding: spacing.topXs),
          Text(
            message,
            style: AppTypography.regular.metadata.copyWith(
              color: AppColors.dark.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (progress case final progress?) ...[
            _SpacingGap(padding: spacing.topComponent),
            _InlineProgress(progress: progress),
          ],
          if (actionLabel case final actionLabel?) ...[
            _SpacingGap(padding: spacing.topComponent),
            CupertinoButton(
              color: colors.actionPrimary,
              borderRadius: radius.compact,
              padding: spacing.compactControl,
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: AppTypography.regular.label.copyWith(
                  color: AppColors.dark.onActionPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _InlineProgress extends StatelessWidget {
  const _InlineProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final normalized = progress.clamp(0, 1).toDouble();
    return Semantics(
      value: '${(normalized * 100).round()}%',
      child: ClipRRect(
        borderRadius: radius.full,
        child: SizedBox(
          width: sizes.progressTrackWidth,
          height: spacing.sm,
          child: ColoredBox(
            color: colors.surfaceRaised,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: normalized,
                child: ColoredBox(color: colors.listening),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _StableSceneStrip extends StatelessWidget {
  const _StableSceneStrip({
    required this.state,
    required this.hasCameraContext,
    required this.onOpenScene,
  });

  final ObserverState state;
  final bool hasCameraContext;
  final VoidCallback onOpenScene;

  @override
  Widget build(BuildContext context) {
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final localizations = AppLocalizations.of(context);
    if (!hasCameraContext) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _SceneChip(
          label: localizations.assistantNoCameraContext,
          icon: CupertinoIcons.camera,
        ),
      );
    }
    if (state.scene.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _SceneChip(
          label: localizations.assistantSceneBuilding,
          icon: CupertinoIcons.viewfinder,
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: sizes.controlHeight),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.scene.objects.length,
        separatorBuilder: (_, _) => _SpacingGap(padding: spacing.startSm),
        itemBuilder: (context, index) {
          final object = state.scene.objects[index];
          return _SceneChip(
            label: localizations.assistantSceneObjectLabel(
              object.label,
              _regionLabel(context, object.region),
            ),
            semanticLabel: localizations.observerSceneObjectLabel(
              object.label,
              object.id,
              _regionLabel(context, object.region),
            ),
            onPressed: onOpenScene,
          );
        },
      ),
    );
  }
}

final class _SceneChip extends StatelessWidget {
  const _SceneChip({
    required this.label,
    this.semanticLabel,
    this.icon,
    this.onPressed,
  });

  final String label;
  final String? semanticLabel;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return Semantics(
      button: onPressed != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: Size.square(sizes.controlHeight),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          padding: spacing.insetSm.copyWith(
            top: spacing.xs,
            bottom: spacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.overlayStrong,
            borderRadius: radius.full,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?) ...[
                Icon(icon, color: colors.textSecondary, size: spacing.component),
                _SpacingGap(padding: spacing.startXs),
              ],
              Text(
                label,
                style: AppTypography.regular.status.copyWith(
                  color: AppColors.dark.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _regionLabel(BuildContext context, SceneRegion region) {
  final localizations = AppLocalizations.of(context);
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

final class _AssistantOutputCard extends StatelessWidget {
  const _AssistantOutputCard({
    required this.state,
    required this.status,
    required this.onOpenSession,
    required this.onStop,
    required this.onReplay,
    required this.onMuteChanged,
    required this.onModelRetry,
    required this.onAnswerRetry,
    required this.onVoiceRetry,
  });

  final ObserverState state;
  final _AssistantVisualStatus status;
  final VoidCallback onOpenSession;
  final VoidCallback onStop;
  final VoidCallback? onReplay;
  final ValueChanged<bool> onMuteChanged;
  final VoidCallback onModelRetry;
  final VoidCallback onAnswerRetry;
  final VoidCallback onVoiceRetry;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final localizations = AppLocalizations.of(context);
    final presentation = _responsePresentation(
      localizations,
      state,
      onModelRetry: onModelRetry,
      onAnswerRetry: onAnswerRetry,
      onVoiceRetry: onVoiceRetry,
    );
    final busy = state.isGenerating || state.isSpeaking;
    return Semantics(
      container: true,
      label: localizations.currentSessionOpenAction,
      liveRegion: status == _AssistantVisualStatus.listening || status == _AssistantVisualStatus.needsAttention,
      onTap: onOpenSession,
      child: GestureDetector(
        onTap: onOpenSession,
        child: AnimatedContainer(
          duration: AppAnimations.regular.normal,
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: sizes.primaryActionHeight * 2 + spacing.sm,
          ),
          padding: spacing.page.copyWith(
            top: spacing.component,
            right: spacing.component,
            bottom: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.overlayStrong,
            borderRadius: radius.card,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.assistantCardStateLabel(
                  _statusLabel(localizations, status),
                ),
                style: AppTypography.regular.status.copyWith(
                  color: AppColors.dark.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              _SpacingGap(padding: spacing.topXs),
              Text(
                presentation.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.regular.body.copyWith(
                  color: presentation.failure ? colors.danger : colors.textPrimary,
                ),
              ),
              _SpacingGap(padding: spacing.topSm),
              Row(
                children: [
                  _CardAction(
                    semanticLabel: busy ? localizations.assistantStopAction : localizations.observerReplayCommentAction,
                    icon: busy ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                    onPressed: busy ? onStop : onReplay,
                  ),
                  _SpacingGap(padding: spacing.startSm),
                  _CardAction(
                    semanticLabel: state.speechMuted
                        ? localizations.observerUnmuteSpeechAction
                        : localizations.observerMuteSpeechAction,
                    icon: state.speechMuted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill,
                    onPressed: () => onMuteChanged(!state.speechMuted),
                  ),
                  if (presentation.action case final action?) ...[
                    _SpacingGap(padding: spacing.startSm),
                    _CardTextAction(
                      label: presentation.actionLabel!,
                      onPressed: action,
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_up,
                    size: spacing.md,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        minimumSize: Size.square(sizes.controlHeight),
        padding: EdgeInsets.zero,
        borderRadius: radius.full,
        color: AppColors.dark.surfaceRaised,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: spacing.md,
          color: AppColors.dark.textPrimary,
        ),
      ),
    );
  }
}

final class _CardTextAction extends StatelessWidget {
  const _CardTextAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return CupertinoButton(
      minimumSize: Size(0, sizes.controlHeight),
      padding: spacing.insetSm,
      borderRadius: radius.full,
      color: AppColors.dark.surfaceRaised,
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTypography.regular.status.copyWith(
          color: AppColors.dark.textPrimary,
        ),
      ),
    );
  }
}

final class _QuestionComposer extends StatefulWidget {
  const _QuestionComposer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.submitting,
    required this.onSubmit,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onStop;

  @override
  State<_QuestionComposer> createState() => _QuestionComposerState();
}

final class _QuestionComposerState extends State<_QuestionComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_QuestionComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final localizations = AppLocalizations.of(context);
    final canSend = widget.enabled && widget.controller.text.trim().isNotEmpty;
    return Container(
      constraints: BoxConstraints(minHeight: sizes.controlHeight),
      padding: spacing.insetSm.copyWith(
        left: spacing.component,
        top: spacing.xs,
        right: spacing.xs,
        bottom: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.dark.overlayStrong,
        borderRadius: radius.card,
        border: Border.all(color: AppColors.dark.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField.borderless(
              key: const ValueKey('assistant-prompt-field'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: !widget.submitting,
              minLines: 1,
              maxLines: 3,
              maxLength: ObserverBloc.manualPromptCharacterLimit,
              placeholder: localizations.assistantScenePromptPlaceholder,
              placeholderStyle: AppTypography.regular.metadata.copyWith(
                color: AppColors.dark.textSecondary,
              ),
              style: AppTypography.regular.body.copyWith(
                color: AppColors.dark.textPrimary,
              ),
              padding: spacing.insetSm.copyWith(left: 0, right: 0),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSend) widget.onSubmit();
              },
            ),
          ),
          CupertinoButton(
            key: const ValueKey('assistant-send-button'),
            minimumSize: Size.square(sizes.controlHeight),
            padding: EdgeInsets.zero,
            borderRadius: radius.full,
            color: AppColors.dark.actionPrimary,
            disabledColor: AppColors.dark.surfaceRaised,
            onPressed: widget.submitting
                ? widget.onStop
                : canSend
                ? widget.onSubmit
                : null,
            child: Icon(
              widget.submitting ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up,
              size: spacing.md,
              color: widget.submitting || canSend ? AppColors.dark.onActionPrimary : AppColors.dark.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

final class _AssistantResponsePresentation {
  const _AssistantResponsePresentation({
    required this.message,
    this.failure = false,
    this.actionLabel,
    this.action,
  });

  final String message;
  final bool failure;
  final String? actionLabel;
  final VoidCallback? action;
}

_AssistantResponsePresentation _responsePresentation(
  AppLocalizations localizations,
  ObserverState state, {
  required VoidCallback onModelRetry,
  required VoidCallback onAnswerRetry,
  required VoidCallback onVoiceRetry,
}) {
  if (state.voiceAnswerDraft.isNotEmpty) {
    return _AssistantResponsePresentation(message: state.voiceAnswerDraft);
  }
  if (state.manualDraftResponse.isNotEmpty) {
    return _AssistantResponsePresentation(message: state.manualDraftResponse);
  }
  if (state.automaticDraft.isNotEmpty) {
    return _AssistantResponsePresentation(message: state.automaticDraft);
  }
  final voiceQuestion = state.voiceQuestionDraft.trim();
  if ((state.voicePhase == VoiceAgentPhase.wakeDetected || state.voicePhase == VoiceAgentPhase.listening) &&
      voiceQuestion.isNotEmpty) {
    return _AssistantResponsePresentation(
      message: localizations.handsFreeAgentRecognizedSpeechLabel(
        voiceQuestion,
      ),
    );
  }
  if (state.modelStatus == ObserverModelStatus.failure) {
    return _AssistantResponsePresentation(
      message: _assistantModelFailureMessage(localizations, state.modelFailure),
      failure: true,
      actionLabel: localizations.retryAction,
      action: onModelRetry,
    );
  }
  if (state.modelStatus != ObserverModelStatus.ready) {
    return _AssistantResponsePresentation(
      message: _assistantModelStatusMessage(localizations, state),
    );
  }
  if (state.manualFailure != null) {
    return _AssistantResponsePresentation(
      message: localizations.assistantGenerationFailureMessage,
      failure: true,
      actionLabel: localizations.assistantRetryAnswerAction,
      action: state.canRetryAnswer ? onAnswerRetry : null,
    );
  }
  if (state.voiceFailure != null || state.asrModelFailure != null) {
    return _AssistantResponsePresentation(
      message: _voiceFailureMessage(localizations, state),
      failure: true,
      actionLabel: localizations.handsFreeAgentRetryAction,
      action: onVoiceRetry,
    );
  }
  if (state.automaticFailure != null) {
    return _AssistantResponsePresentation(
      message: localizations.observerGenerationFailureMessage,
      failure: true,
    );
  }
  if (state.speechFailure != null) {
    return _AssistantResponsePresentation(
      message: localizations.observerSpeechFailureMessage,
      failure: true,
    );
  }
  for (final message in state.messages.reversed) {
    if (message.role == ConversationRole.assistant) {
      return _AssistantResponsePresentation(message: message.content);
    }
  }
  if (state.comments.isNotEmpty) {
    return _AssistantResponsePresentation(message: state.comments.last.text);
  }
  if (state.isGenerating) {
    return _AssistantResponsePresentation(
      message: localizations.assistantThinkingMessage,
    );
  }
  return _AssistantResponsePresentation(
    message: localizations.assistantEmptyCardMessage,
  );
}

String _assistantModelStatusMessage(
  AppLocalizations localizations,
  ObserverState state,
) {
  return switch (state.modelStatus) {
    ObserverModelStatus.idle => localizations.assistantModelNotStartedMessage,
    ObserverModelStatus.loading => localizations.assistantModelPreparingMessage,
    ObserverModelStatus.downloading => localizations.assistantModelDownloadingMessage(
      ((state.modelDownloadProgress ?? 0) * 100).round(),
    ),
    ObserverModelStatus.verifying => localizations.assistantModelVerifyingMessage,
    ObserverModelStatus.suspended => localizations.assistantModelSuspendedMessage,
    ObserverModelStatus.failure => _assistantModelFailureMessage(localizations, state.modelFailure),
    ObserverModelStatus.ready => localizations.assistantReadyMessage,
  };
}

String _assistantModelFailureMessage(
  AppLocalizations localizations,
  AppFailure? failure,
) {
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

String _voiceFailureMessage(
  AppLocalizations localizations,
  ObserverState state,
) {
  final failure = state.asrModelFailure ?? state.voiceFailure;
  if (failure?.code == 'microphone_permission_restricted') {
    return localizations.handsFreeAgentMicrophoneRestrictedFailureMessage;
  }
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
      _displayWakePhrase(state.wakePhrase),
    );
  }
  if (_isVoiceAnswerFailure(failure?.code)) {
    return localizations.handsFreeAgentAnswerFailureMessage;
  }
  if (failure is DeviceUnavailableFailure || failure?.code.startsWith('asr_') == true) {
    return localizations.handsFreeAgentRecognitionFailureMessage;
  }
  return localizations.handsFreeAgentFailureMessage;
}

String _displayWakePhrase(String phrase) {
  final normalized = phrase.trim();
  if (normalized.isEmpty) return normalized;
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

bool _isVoiceAnswerFailure(String? code) {
  return code?.startsWith('voice_assistant_') == true ||
      code?.startsWith('voice_answer_') == true ||
      code?.startsWith('assistant_generation') == true ||
      code == 'assistant_empty_response';
}

String _statusLabel(
  AppLocalizations localizations,
  _AssistantVisualStatus status,
) {
  return switch (status) {
    _AssistantVisualStatus.starting => localizations.assistantStatusStarting,
    _AssistantVisualStatus.watching => localizations.assistantStatusWatching,
    _AssistantVisualStatus.listening => localizations.assistantStatusListening,
    _AssistantVisualStatus.thinking => localizations.assistantStatusThinking,
    _AssistantVisualStatus.speaking => localizations.assistantStatusSpeaking,
    _AssistantVisualStatus.paused => localizations.assistantStatusPaused,
    _AssistantVisualStatus.needsAttention => localizations.assistantStatusNeedsAttention,
  };
}

void _setPaused(BuildContext context, {required bool paused}) {
  context.read<CameraBloc>().add(
    paused ? const CameraDisableRequested() : const CameraEnableRequested(),
  );
  context.read<ObserverBloc>().add(
    paused ? const ObservationStopped() : const ObservationStarted(),
  );
}

void _stopActiveWork(BuildContext context, ObserverState state) {
  if (state.activeGeneration == ObserverGenerationKind.manual) {
    context.read<ObserverBloc>().add(
      const ObserverManualGenerationCancelled(),
    );
  } else if (state.isGenerating) {
    context.read<ObserverBloc>().add(const ObservationStopped());
  } else if (state.isSpeaking) {
    context.read<ObserverBloc>().add(const ObserverSpeechStopped());
  }
}

bool _hasReplayableResponse(ObserverState state) {
  return _latestReplayableEntry(state) != null;
}

void _replayLatestResponse(BuildContext context, ObserverState state) {
  final entry = _latestReplayableEntry(state);
  if (entry == null) return;
  final bloc = context.read<ObserverBloc>();
  switch (entry.kind) {
    case ObserverSessionEntryKind.comment:
      bloc.add(ObserverCommentReplayRequested(entry.index));
    case ObserverSessionEntryKind.message:
      bloc.add(ObserverMessageReplayRequested(entry.index));
  }
}

ObserverSessionEntry? _latestReplayableEntry(ObserverState state) {
  for (final entry in _orderedSessionEntries(state).reversed) {
    switch (entry.kind) {
      case ObserverSessionEntryKind.comment:
        if (entry.index < state.comments.length) return entry;
      case ObserverSessionEntryKind.message:
        if (entry.index < state.messages.length && state.messages[entry.index].role == ConversationRole.assistant) {
          return entry;
        }
    }
  }
  return null;
}

void _showCurrentSession(BuildContext context, ObserverState state) {
  final observerBloc = context.read<ObserverBloc>();
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      barrierColor: AppColors.dark.overlaySoft,
      builder: (_) => _CurrentSessionSheet(
        state: state,
        onCommentReplay: (index) {
          observerBloc.add(ObserverCommentReplayRequested(index));
        },
        onMessageReplay: (index) {
          observerBloc.add(ObserverMessageReplayRequested(index));
        },
      ),
    ),
  );
}

void _showStableScene(BuildContext context, ObserverState state) {
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      barrierColor: AppColors.dark.overlaySoft,
      builder: (_) => _StableSceneSheet(state: state),
    ),
  );
}

final class _StableSceneSheet extends StatelessWidget {
  const _StableSceneSheet({required this.state});

  final ObserverState state;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const spacing = AppSpacing.regular;
    final localizations = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.58,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: radius.sheet,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHeader(
                title: localizations.observerSceneTitle,
                subtitle: state.scene.isEmpty ? localizations.observerEmptySceneMessage : null,
              ),
              if (state.scene.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: spacing.page,
                    itemCount: state.scene.objects.length,
                    separatorBuilder: (_, _) => _SpacingGap(padding: spacing.topComponent),
                    itemBuilder: (context, index) {
                      final object = state.scene.objects[index];
                      return Semantics(
                        container: true,
                        label: localizations.observerSceneObjectLabel(
                          object.label,
                          object.id,
                          _regionLabel(context, object.region),
                        ),
                        excludeSemantics: true,
                        child: _SessionEntry(
                          role: '${object.label} #${object.id}',
                          content: _regionLabel(context, object.region),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: sizes.sheetGrabberWidth,
            height: sizes.sheetGrabberHeight,
            margin: spacing.topSm,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: radius.full,
            ),
          ),
        ),
        Padding(
          padding: spacing.sessionSheetHeader,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTypography.regular.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: AppTypography.regular.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              CupertinoButton(
                minimumSize: Size.square(sizes.controlHeight),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CurrentSessionSheet extends StatelessWidget {
  const _CurrentSessionSheet({
    required this.state,
    required this.onCommentReplay,
    required this.onMessageReplay,
  });

  final ObserverState state;
  final ValueChanged<int> onCommentReplay;
  final ValueChanged<int> onMessageReplay;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    final localizations = AppLocalizations.of(context);
    final hasContent = state.comments.isNotEmpty || state.messages.isNotEmpty;
    final entries = _orderedSessionEntries(state);
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.62,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: radius.sheet,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            _SheetHeader(
              title: localizations.currentSessionTitle,
              subtitle: localizations.currentSessionClearsMessage,
            ),
            ConstrainedBox(
              constraints: BoxConstraints.tightFor(height: sizes.hairlineWidth),
              child: ColoredBox(color: colors.border),
            ),
            Expanded(
              child: hasContent
                  ? ListView(
                      padding: spacing.page,
                      children: [
                        for (final entry in entries)
                          _sessionEntryWidget(
                            localizations,
                            state,
                            entry,
                            onCommentReplay: onCommentReplay,
                            onMessageReplay: onMessageReplay,
                          ),
                      ],
                    )
                  : Center(
                      child: Text(
                        localizations.currentSessionEmptyMessage,
                        style: AppTypography.regular.body.copyWith(
                          color: AppColors.dark.textSecondary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

List<ObserverSessionEntry> _orderedSessionEntries(ObserverState state) {
  if (state.sessionEntries.isNotEmpty) return state.sessionEntries;
  return [
    for (var index = 0; index < state.comments.length; index += 1)
      ObserverSessionEntry(
        kind: ObserverSessionEntryKind.comment,
        index: index,
      ),
    for (var index = 0; index < state.messages.length; index += 1)
      ObserverSessionEntry(
        kind: ObserverSessionEntryKind.message,
        index: index,
      ),
  ];
}

Widget _sessionEntryWidget(
  AppLocalizations localizations,
  ObserverState state,
  ObserverSessionEntry entry, {
  required ValueChanged<int> onCommentReplay,
  required ValueChanged<int> onMessageReplay,
}) {
  return switch (entry.kind) {
    ObserverSessionEntryKind.comment when entry.index < state.comments.length => _SessionEntry(
      role: localizations.assistantRoleLabel,
      content: state.comments[entry.index].text,
      onReplay: state.speechMuted ? null : () => onCommentReplay(entry.index),
    ),
    ObserverSessionEntryKind.message when entry.index < state.messages.length => _SessionEntry(
      role: state.messages[entry.index].role == ConversationRole.user
          ? localizations.assistantUserRoleLabel
          : localizations.assistantRoleLabel,
      content: state.messages[entry.index].content,
      onReplay: state.speechMuted || state.messages[entry.index].role == ConversationRole.user
          ? null
          : () => onMessageReplay(entry.index),
    ),
    _ => const SizedBox.shrink(),
  };
}

final class _SessionEntry extends StatelessWidget {
  const _SessionEntry({
    required this.role,
    required this.content,
    this.onReplay,
  });

  final String role;
  final String content;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    return Padding(
      padding: spacing.bottomComponent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  role,
                  style: AppTypography.regular.status.copyWith(
                    color: AppColors.dark.textSecondary,
                  ),
                ),
              ),
              if (onReplay case final onReplay?)
                Semantics(
                  button: true,
                  label: AppLocalizations.of(
                    context,
                  ).observerReplayCommentAction,
                  child: CupertinoButton(
                    minimumSize: Size.square(
                      AppSizes.regular.controlHeight,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onReplay,
                    child: Icon(
                      CupertinoIcons.play_fill,
                      size: AppSpacing.regular.md,
                      color: AppColors.dark.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          _SpacingGap(padding: spacing.topXs),
          Text(
            content,
            style: AppTypography.regular.body.copyWith(
              color: AppColors.dark.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SpacingGap extends StatelessWidget {
  const _SpacingGap({required this.padding});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(padding: padding);
}
