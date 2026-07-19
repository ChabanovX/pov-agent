import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic spacing values and insets used by application layouts.
@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  /// Creates spacing tokens from the supplied scale.
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  /// The extra-small spacing value in logical pixels.
  final double xs;

  /// The small spacing value in logical pixels.
  final double sm;

  /// The medium spacing value in logical pixels.
  final double md;

  /// The large spacing value in logical pixels.
  final double lg;

  /// The extra-large spacing value in logical pixels.
  final double xl;

  /// Equal page insets derived from [lg].
  EdgeInsets get page => EdgeInsets.all(lg);

  /// Equal small insets derived from [sm].
  EdgeInsets get insetSm => EdgeInsets.all(sm);

  /// A top-only inset derived from [md].
  EdgeInsets get topMd => EdgeInsets.only(top: md);

  /// A top-only inset derived from [lg].
  EdgeInsets get topLg => EdgeInsets.only(top: lg);

  /// Section insets using [lg] horizontally and [md] vertically.
  EdgeInsets get section => EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  /// The standard application spacing scale.
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
