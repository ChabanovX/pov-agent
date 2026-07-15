import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

@immutable
final class AppRadius extends ThemeExtension<AppRadius> {
  const AppRadius({
    required this.sm,
    required this.md,
    required this.lg,
  });

  final BorderRadius sm;
  final BorderRadius md;
  final BorderRadius lg;

  static const regular = AppRadius(
    sm: BorderRadius.all(Radius.circular(kRadiusSm)),
    md: BorderRadius.all(Radius.circular(kRadiusMd)),
    lg: BorderRadius.all(Radius.circular(kRadiusLg)),
  );

  @override
  AppRadius copyWith({
    BorderRadius? sm,
    BorderRadius? md,
    BorderRadius? lg,
  }) {
    return AppRadius(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
    );
  }

  @override
  AppRadius lerp(ThemeExtension<AppRadius>? other, double t) {
    if (other is! AppRadius) return this;
    return AppRadius(
      sm: BorderRadius.lerp(sm, other.sm, t)!,
      md: BorderRadius.lerp(md, other.md, t)!,
      lg: BorderRadius.lerp(lg, other.lg, t)!,
    );
  }
}
