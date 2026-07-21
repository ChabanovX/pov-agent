import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic colors used by application surfaces and content.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  /// Creates a semantic application color palette.
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.onActionPrimary,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.overlayStrong,
    required this.overlaySoft,
    required this.cameraScrimTop,
    required this.cameraScrimClear,
    required this.cameraScrimMiddle,
    required this.cameraScrimBottom,
    required this.onSurface,
    required this.muted,
    required this.border,
    required this.success,
    required this.listening,
    required this.warning,
    required this.danger,
  });

  /// The primary action color.
  final Color primary;

  /// The legacy light foreground retained for existing dark overlays.
  final Color onPrimary;

  /// The content color displayed over [actionPrimary].
  final Color onActionPrimary;

  /// The application canvas color.
  final Color background;

  /// The color for raised or grouped surfaces.
  final Color surface;

  /// The color for selected rows and elevated controls.
  final Color surfaceRaised;

  /// The near-opaque camera overlay used for maximum legibility.
  final Color overlayStrong;

  /// The secondary camera scrim color.
  final Color overlaySoft;

  /// The top camera-overlay gradient color.
  final Color cameraScrimTop;

  /// The transparent camera-overlay gradient color.
  final Color cameraScrimClear;

  /// The middle camera-overlay gradient color.
  final Color cameraScrimMiddle;

  /// The bottom camera-overlay gradient color.
  final Color cameraScrimBottom;

  /// The primary content color displayed over [surface].
  final Color onSurface;

  /// The color for secondary or de-emphasized content.
  final Color muted;

  /// The color for dividers and inactive outlines.
  final Color border;

  /// The color for ready, verified, and watching states.
  final Color success;

  /// The color for wake-detected and listening states.
  final Color listening;

  /// The color for recoverable degradation and thermal warnings.
  final Color warning;

  /// The color for destructive actions and failure states.
  final Color danger;

  /// The dark application color palette.
  static const AppColors dark = AppColors(
    primary: Color(kColorActionPrimaryValue),
    onPrimary: Color(kColorTextPrimaryValue),
    onActionPrimary: Color(kColorOnActionPrimaryValue),
    background: Color(kColorBackgroundValue),
    surface: Color(kColorSurfaceValue),
    surfaceRaised: Color(kColorSurfaceRaisedValue),
    overlayStrong: Color(kColorOverlayStrongValue),
    overlaySoft: Color(kColorOverlaySoftValue),
    cameraScrimTop: Color(kColorCameraScrimTopValue),
    cameraScrimClear: Color(kColorCameraScrimClearValue),
    cameraScrimMiddle: Color(kColorCameraScrimMiddleValue),
    cameraScrimBottom: Color(kColorCameraScrimBottomValue),
    onSurface: Color(kColorTextPrimaryValue),
    muted: Color(kColorTextSecondaryValue),
    border: Color(kColorBorderValue),
    success: Color(kColorSuccessValue),
    listening: Color(kColorListeningValue),
    warning: Color(kColorWarningValue),
    danger: Color(kColorDangerValue),
  );

  /// Compatibility palette used by screens awaiting semantic-token migration.
  static const AppColors light = AppColors(
    primary: Color(kColorActionPrimaryValue),
    onPrimary: Color(kColorTextPrimaryValue),
    onActionPrimary: Color(kColorOnActionPrimaryValue),
    background: Color(kColorBackgroundValue),
    surface: Color(kColorSurfaceValue),
    surfaceRaised: Color(kColorSurfaceRaisedValue),
    overlayStrong: Color(kColorOverlayStrongValue),
    overlaySoft: Color(kColorOverlaySoftValue),
    cameraScrimTop: Color(kColorCameraScrimTopValue),
    cameraScrimClear: Color(kColorCameraScrimClearValue),
    cameraScrimMiddle: Color(kColorCameraScrimMiddleValue),
    cameraScrimBottom: Color(kColorCameraScrimBottomValue),
    onSurface: Color(kColorTextPrimaryValue),
    muted: Color(kColorTextSecondaryValue),
    border: Color(kColorBorderValue),
    success: Color(kColorSuccessValue),
    listening: Color(kColorListeningValue),
    warning: Color(kColorWarningValue),
    danger: Color(kColorDangerValue),
  );

  /// The primary action color.
  Color get actionPrimary => primary;

  /// The primary text and icon color.
  Color get textPrimary => onSurface;

  /// The secondary text and icon color.
  Color get textSecondary => muted;

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? onActionPrimary,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? overlayStrong,
    Color? overlaySoft,
    Color? cameraScrimTop,
    Color? cameraScrimClear,
    Color? cameraScrimMiddle,
    Color? cameraScrimBottom,
    Color? onSurface,
    Color? muted,
    Color? border,
    Color? success,
    Color? listening,
    Color? warning,
    Color? danger,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      onActionPrimary: onActionPrimary ?? this.onActionPrimary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      overlayStrong: overlayStrong ?? this.overlayStrong,
      overlaySoft: overlaySoft ?? this.overlaySoft,
      cameraScrimTop: cameraScrimTop ?? this.cameraScrimTop,
      cameraScrimClear: cameraScrimClear ?? this.cameraScrimClear,
      cameraScrimMiddle: cameraScrimMiddle ?? this.cameraScrimMiddle,
      cameraScrimBottom: cameraScrimBottom ?? this.cameraScrimBottom,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      success: success ?? this.success,
      listening: listening ?? this.listening,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onActionPrimary: Color.lerp(
        onActionPrimary,
        other.onActionPrimary,
        t,
      )!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      overlayStrong: Color.lerp(overlayStrong, other.overlayStrong, t)!,
      overlaySoft: Color.lerp(overlaySoft, other.overlaySoft, t)!,
      cameraScrimTop: Color.lerp(cameraScrimTop, other.cameraScrimTop, t)!,
      cameraScrimClear: Color.lerp(
        cameraScrimClear,
        other.cameraScrimClear,
        t,
      )!,
      cameraScrimMiddle: Color.lerp(
        cameraScrimMiddle,
        other.cameraScrimMiddle,
        t,
      )!,
      cameraScrimBottom: Color.lerp(
        cameraScrimBottom,
        other.cameraScrimBottom,
        t,
      )!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      listening: Color.lerp(listening, other.listening, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
