import 'package:flutter/cupertino.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';

/// Displays the native camera preview with Cupertino camera controls.
final class CameraWidget extends StatelessWidget {
  const CameraWidget({
    required this.previewBuilder,
    required this.onDisableCamera,
    required this.onToggleCamera,
    required this.canToggleCamera,
    super.key,
  });

  final WidgetBuilder previewBuilder;
  final VoidCallback onDisableCamera;
  final VoidCallback onToggleCamera;
  final bool canToggleCamera;

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
          previewBuilder(context),
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
        ],
      ),
    );
  }
}
