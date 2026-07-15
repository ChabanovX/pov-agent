import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.danger,
  });

  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color muted;
  final Color danger;

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
