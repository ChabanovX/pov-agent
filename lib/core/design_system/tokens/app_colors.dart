import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

/// Semantic colors used by application surfaces and content.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  /// Creates a semantic application color palette.
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.danger,
  });

  /// The primary accent color.
  final Color primary;

  /// The content color displayed over [primary].
  final Color onPrimary;

  /// The application canvas color.
  final Color background;

  /// The color for raised or grouped surfaces.
  final Color surface;

  /// The primary content color displayed over [surface].
  final Color onSurface;

  /// The color for secondary or de-emphasized content.
  final Color muted;

  /// The color for destructive actions and failure states.
  final Color danger;

  /// The light application color palette.
  static const light = AppColors(
    primary: Color(kColorPrimaryLightValue),
    onPrimary: Color(kColorOnPrimaryLightValue),
    background: Color(kColorBackgroundLightValue),
    surface: Color(kColorSurfaceLightValue),
    onSurface: Color(kColorOnSurfaceLightValue),
    muted: Color(kColorMutedLightValue),
    danger: Color(kColorDangerLightValue),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? background,
    Color? surface,
    Color? onSurface,
    Color? muted,
    Color? danger,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
