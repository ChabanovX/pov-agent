import 'package:flutter/cupertino.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';

/// A layout for the observation surface, diagnostics, and camera controls.
final class CameraWidget extends StatelessWidget {
  /// Creates a camera layout around an app-composed observation surface.
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

  /// Builds the native or recorded observation surface.
  final WidgetBuilder surfaceBuilder;

  /// Called when the user requests that observation be disabled.
  final VoidCallback onDisableCamera;

  /// Called when the user requests the next available lens.
  final VoidCallback onToggleCamera;

  /// Whether the lens-toggle control is available.
  final bool canToggleCamera;

  /// Whether observation controls are visible.
  final bool controlsVisible;

  /// The optional inference diagnostics displayed over the surface.
  final ObservationDiagnostics? diagnostics;

  /// The optional state overlay displayed above the surface and controls.
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
          if (overlay case final overlay?) BlockSemantics(child: overlay),
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
