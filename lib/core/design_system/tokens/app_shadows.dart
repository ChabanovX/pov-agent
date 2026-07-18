import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

/// Semantic shadows used to express application elevation.
@immutable
final class AppShadows extends ThemeExtension<AppShadows> {
  /// Creates shadow tokens from the supplied elevation levels.
  const AppShadows({
    required this.level1,
  });

  /// The shadow for the first elevation level.
  final List<BoxShadow> level1;

  /// The standard application shadows.
  static const regular = AppShadows(
    level1: [
      BoxShadow(
        blurRadius: kShadowLevel1BlurRadius,
        color: Color(kShadowLevel1ColorValue),
        offset: Offset(kShadowLevel1OffsetX, kShadowLevel1OffsetY),
      ),
    ],
  );

  @override
  AppShadows copyWith({
    List<BoxShadow>? level1,
  }) {
    return AppShadows(
      level1: level1 ?? this.level1,
    );
  }

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) return this;
    return AppShadows(
      level1: BoxShadow.lerpList(level1, other.level1, t) ?? level1,
    );
  }
}
