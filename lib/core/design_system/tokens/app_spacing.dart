import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  EdgeInsets get page => EdgeInsets.all(lg);

  EdgeInsets get section => EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  static const regular = AppSpacing(
    xs: kSpacingXs,
    sm: kSpacingSm,
    md: kSpacingMd,
    lg: kSpacingLg,
    xl: kSpacingXl,
  );

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
