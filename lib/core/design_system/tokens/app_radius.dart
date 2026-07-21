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
    required this.action,
    required this.sheet,
  });

  /// The small component corner radius.
  final BorderRadius sm;

  /// The medium component corner radius.
  final BorderRadius md;

  /// The large component corner radius.
  final BorderRadius lg;

  /// The primary-action corner radius.
  final BorderRadius action;

  /// The top-only radius for native-style modal sheets.
  final BorderRadius sheet;

  /// The compact overlay and control corner radius.
  BorderRadius get compact => md;

  /// The Assistant and model-card corner radius.
  BorderRadius get card => lg;

  /// The fully rounded radius used by capsules and circular controls.
  BorderRadius get full {
    return const BorderRadius.all(Radius.circular(kRadiusFull));
  }

  /// The standard application corner radii.
  static const regular = AppRadius(
    sm: BorderRadius.all(Radius.circular(kRadiusSm)),
    md: BorderRadius.all(Radius.circular(kRadiusMd)),
    lg: BorderRadius.all(Radius.circular(kRadiusLg)),
    action: BorderRadius.all(Radius.circular(kRadiusAction)),
    sheet: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
  );

  @override
  AppRadius copyWith({
    BorderRadius? sm,
    BorderRadius? md,
    BorderRadius? lg,
    BorderRadius? action,
    BorderRadius? sheet,
  }) {
    return AppRadius(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      action: action ?? this.action,
      sheet: sheet ?? this.sheet,
    );
  }

  @override
  AppRadius lerp(ThemeExtension<AppRadius>? other, double t) {
    if (other is! AppRadius) return this;
    return AppRadius(
      sm: BorderRadius.lerp(sm, other.sm, t)!,
      md: BorderRadius.lerp(md, other.md, t)!,
      lg: BorderRadius.lerp(lg, other.lg, t)!,
      action: BorderRadius.lerp(action, other.action, t)!,
      sheet: BorderRadius.lerp(sheet, other.sheet, t)!,
    );
  }
}
