import 'package:flutter/cupertino.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';

/// Displays the native YOLO surface, diagnostics, and camera controls.
final class CameraWidget extends StatelessWidget {
  const CameraWidget({
    required this.surfaceBuilder,
    required this.onDisableCamera,
    required this.onToggleCamera,
    required this.canToggleCamera,
    required this.controlsVisible,
    this.diagnostics,
    this.overlay,
    super.key,
  });

  final WidgetBuilder surfaceBuilder;
  final VoidCallback onDisableCamera;
  final VoidCallback onToggleCamera;
  final bool canToggleCamera;
  final bool controlsVisible;
  final ObservationDiagnostics? diagnostics;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const radius = AppRadius.regular;

    return ColoredBox(
      color: colors.onSurface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          surfaceBuilder(context),
          if (diagnostics case final diagnostics?)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: spacing.section,
                  child: _DiagnosticsPill(diagnostics: diagnostics),
                ),
              ),
            ),
          if (controlsVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: spacing.section,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Semantics(
                        button: true,
                        label: localizations.cameraDisableAction,
                        child: CupertinoButton(
                          borderRadius: radius.lg,
                          color: colors.surface,
                          onPressed: onDisableCamera,
                          padding: spacing.insetSm,
                          child: Icon(
                            CupertinoIcons.power,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      if (canToggleCamera)
                        Semantics(
                          button: true,
                          label: localizations.cameraSwitchAction,
                          child: CupertinoButton(
                            borderRadius: radius.lg,
                            color: colors.surface,
                            onPressed: onToggleCamera,
                            padding: spacing.insetSm,
                            child: Icon(
                              CupertinoIcons.camera_rotate,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ?overlay,
        ],
      ),
    );
  }
}

final class _DiagnosticsPill extends StatelessWidget {
  const _DiagnosticsPill({required this.diagnostics});

  final ObservationDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const radius = AppRadius.regular;
    const typography = AppTypography.regular;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.72),
        borderRadius: radius.md,
      ),
      child: Padding(
        padding: spacing.insetSm,
        child: Text(
          '${localizations.cameraFpsLabel(diagnostics.framesPerSecond.toStringAsFixed(1))} · '
          '${localizations.cameraInferenceLabel(diagnostics.inferenceTimeMs.toStringAsFixed(1))}',
          style: typography.label.copyWith(color: colors.onPrimary),
        ),
      ),
    );
  }
}
