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
    required this.previewBuilder,
    super.key,
  });

  final WidgetBuilder previewBuilder;

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
            return switch (state.status) {
              CameraStatus.initial || CameraStatus.initializing || CameraStatus.switching => const Center(
                child: CupertinoActivityIndicator(),
              ),
              CameraStatus.enabled => CameraWidget(
                previewBuilder: previewBuilder,
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
              ),
              CameraStatus.disabled => _CameraMessage(
                icon: CupertinoIcons.camera,
                message: localizations.cameraDisabledMessage,
                actionLabel: localizations.cameraEnableAction,
                onAction: () {
                  context.read<CameraBloc>().add(
                    const CameraEnableRequested(),
                  );
                },
              ),
              CameraStatus.failure => _CameraFailureMessage(
                failure: state.failure,
                onRetry: () {
                  context.read<CameraBloc>().add(
                    const CameraRetryRequested(),
                  );
                },
              ),
            };
          },
        ),
      ),
    );
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

    return Center(
      child: Padding(
        padding: spacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.muted),
            Padding(
              padding: spacing.topMd,
              child: Text(
                message,
                style: typography.body.copyWith(color: colors.onSurface),
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
