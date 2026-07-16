import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_state.dart';
import 'package:some_camera_with_llm/features/camera/presentation/widgets/camera_widget.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

final class CameraPage extends StatelessWidget {
  const CameraPage({
    required this.surfaceBuilder,
    super.key,
  });

  final WidgetBuilder surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(localizations.cameraTabLabel),
      ),
      child: SafeArea(
        bottom: false,
        child: BlocBuilder<CameraBloc, CameraState>(
          builder: (context, state) {
            if (!state.surfaceMounted) {
              if (state.cameraFailure != null) {
                return _CameraFailureMessage(
                  failure: state.cameraFailure,
                  onRetry: () {
                    context.read<CameraBloc>().add(
                      const CameraRetryRequested(),
                    );
                  },
                );
              }
              return const Center(child: CupertinoActivityIndicator());
            }

            final observationVisible =
                state.status == CameraStatus.enabled &&
                state.modelStatus == ObservationModelStatus.ready &&
                state.failure == null;
            return CameraWidget(
              surfaceBuilder: surfaceBuilder,
              controlsVisible: observationVisible,
              diagnostics: observationVisible ? state.diagnostics : null,
              overlay: _overlayFor(context, state),
              onDisableCamera: () {
                context.read<CameraBloc>().add(
                  const CameraDisableRequested(),
                );
              },
              onToggleCamera: () {
                context.read<CameraBloc>().add(
                  const CameraLensToggleRequested(),
                );
              },
              canToggleCamera: state.canToggleLens,
            );
          },
        ),
      ),
    );
  }

  Widget? _overlayFor(BuildContext context, CameraState state) {
    final localizations = AppLocalizations.of(context);
    if (state.modelFailure != null) {
      final message = state.modelFailure is NetworkFailure
          ? localizations.cameraModelNetworkFailureMessage
          : localizations.cameraModelFailureMessage;
      return _CameraMessage(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: message,
        actionLabel: localizations.retryAction,
        onAction: () {
          context.read<CameraBloc>().add(const CameraRetryRequested());
        },
      );
    }
    if (state.cameraFailure != null) {
      return _CameraFailureMessage(
        failure: state.cameraFailure,
        onRetry: () {
          context.read<CameraBloc>().add(const CameraRetryRequested());
        },
      );
    }
    if (state.status == CameraStatus.disabled) {
      return _CameraMessage(
        icon: CupertinoIcons.camera,
        message: localizations.cameraDisabledMessage,
        actionLabel: localizations.cameraEnableAction,
        onAction: () {
          context.read<CameraBloc>().add(const CameraEnableRequested());
        },
      );
    }
    if (state.modelStatus == ObservationModelStatus.downloading) {
      final progress = state.modelDownloadProgress ?? 0;
      return _CameraLoadingMessage(
        message: localizations.cameraModelDownloadingMessage(
          (progress * 100).round(),
        ),
        progress: progress,
      );
    }
    if (state.modelStatus != ObservationModelStatus.ready) {
      return _CameraLoadingMessage(
        message: localizations.cameraModelPreparingMessage,
      );
    }
    if (state.status == CameraStatus.initializing || state.status == CameraStatus.switching) {
      return _CameraLoadingMessage(
        message: localizations.cameraStartingMessage,
      );
    }
    return null;
  }
}

final class _CameraFailureMessage extends StatelessWidget {
  const _CameraFailureMessage({
    required this.failure,
    required this.onRetry,
  });

  final AppFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final message = switch (failure) {
      PermissionDeniedFailure() => localizations.cameraPermissionDeniedMessage,
      DeviceUnavailableFailure() => localizations.cameraUnavailableMessage,
      _ => localizations.cameraFailureMessage,
    };

    return _CameraMessage(
      icon: CupertinoIcons.exclamationmark_triangle,
      message: message,
      actionLabel: localizations.retryAction,
      onAction: onRetry,
    );
  }
}

final class _CameraLoadingMessage extends StatelessWidget {
  const _CameraLoadingMessage({
    required this.message,
    this.progress,
  });

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const sizes = AppSizes.regular;
    const typography = AppTypography.regular;
    const radius = AppRadius.regular;

    return _CameraOverlay(
      child: Padding(
        padding: spacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(color: colors.onPrimary),
            Padding(
              padding: spacing.topMd,
              child: Text(
                message,
                style: typography.body.copyWith(color: colors.onPrimary),
                textAlign: TextAlign.center,
              ),
            ),
            if (progress case final progress?)
              Padding(
                padding: spacing.topMd,
                child: ClipRRect(
                  borderRadius: radius.sm,
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(
                      width: sizes.progressTrackWidth,
                      height: spacing.xs,
                    ),
                    child: ColoredBox(
                      color: colors.muted,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0, 1),
                          child: ColoredBox(color: colors.primary),
                        ),
                      ),
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

final class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    const colors = AppColors.light;
    const typography = AppTypography.regular;

    return _CameraOverlay(
      child: Padding(
        padding: spacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.onPrimary),
            Padding(
              padding: spacing.topMd,
              child: Text(
                message,
                style: typography.body.copyWith(color: colors.onPrimary),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: spacing.topLg,
              child: CupertinoButton.filled(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CameraOverlay extends StatelessWidget {
  const _CameraOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    return ColoredBox(
      color: colors.onSurface.withValues(alpha: 0.88),
      child: Center(child: child),
    );
  }
}
