import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic corner radii used by application components.
@immutable
final class AppRadius extends ThemeExtension<AppRadius> {
  /// Creates corner-radius tokens from the supplied values.
  const AppRadius({
    required this.sm,
    required this.md,
    required this.lg,
  });

  /// The small component corner radius.
  final BorderRadius sm;

  /// The medium component corner radius.
  final BorderRadius md;

  /// The large component corner radius.
  final BorderRadius lg;

  /// The standard application corner radii.
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
