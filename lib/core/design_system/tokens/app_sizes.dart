import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

@immutable
final class AppSizes extends ThemeExtension<AppSizes> {
  const AppSizes({
    required this.icon,
    required this.controlHeight,
    required this.maxContentWidth,
  });

  final double icon;
  final double controlHeight;
  final double maxContentWidth;

  static const regular = AppSizes(
    icon: kIconSize,
    controlHeight: kControlHeight,
    maxContentWidth: kMaxContentWidth,
  );

  @override
  AppSizes copyWith({
    double? icon,
    double? controlHeight,
    double? maxContentWidth,
  }) {
    return AppSizes(
      icon: icon ?? this.icon,
      controlHeight: controlHeight ?? this.controlHeight,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
    );
  }

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    return AppSizes(
      icon: _lerp(icon, other.icon, t),
      controlHeight: _lerp(controlHeight, other.controlHeight, t),
      maxContentWidth: _lerp(maxContentWidth, other.maxContentWidth, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
