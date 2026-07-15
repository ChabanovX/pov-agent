import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

@immutable
final class AppAnimations extends ThemeExtension<AppAnimations> {
  const AppAnimations({
    required this.fast,
    required this.normal,
    required this.slow,
  });

  final Duration fast;
  final Duration normal;
  final Duration slow;

  static const regular = AppAnimations(
    fast: kAnimationFast,
    normal: kAnimationNormal,
    slow: kAnimationSlow,
  );

  @override
  AppAnimations copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
  }) {
    return AppAnimations(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
    );
  }

  @override
  AppAnimations lerp(ThemeExtension<AppAnimations>? other, double t) {
    if (other is! AppAnimations) return this;
    return AppAnimations(
      fast: _lerpDuration(fast, other.fast, t),
      normal: _lerpDuration(normal, other.normal, t),
      slow: _lerpDuration(slow, other.slow, t),
    );
  }
}

Duration _lerpDuration(Duration begin, Duration end, double t) {
  final micros = begin.inMicroseconds + ((end.inMicroseconds - begin.inMicroseconds) * t).round();
  return Duration(microseconds: micros);
}
