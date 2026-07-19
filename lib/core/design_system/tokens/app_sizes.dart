import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic component dimensions used throughout the application.
@immutable
final class AppSizes extends ThemeExtension<AppSizes> {
  /// Creates component-size tokens from the supplied dimensions.
  const AppSizes({
    required this.icon,
    required this.controlHeight,
    required this.progressTrackWidth,
    required this.maxContentWidth,
  });

  /// The standard icon size in logical pixels.
  final double icon;

  /// The standard interactive-control height in logical pixels.
  final double controlHeight;

  /// The model-download progress track width in logical pixels.
  final double progressTrackWidth;

  /// The maximum readable content width in logical pixels.
  final double maxContentWidth;

  /// The standard application component dimensions.
  static const regular = AppSizes(
    icon: kIconSize,
    controlHeight: kControlHeight,
    progressTrackWidth: kProgressTrackWidth,
    maxContentWidth: kMaxContentWidth,
  );

  @override
  AppSizes copyWith({
    double? icon,
    double? controlHeight,
    double? progressTrackWidth,
    double? maxContentWidth,
  }) {
    return AppSizes(
      icon: icon ?? this.icon,
      controlHeight: controlHeight ?? this.controlHeight,
      progressTrackWidth: progressTrackWidth ?? this.progressTrackWidth,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
    );
  }

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    return AppSizes(
      icon: _lerp(icon, other.icon, t),
      controlHeight: _lerp(controlHeight, other.controlHeight, t),
      progressTrackWidth: _lerp(
        progressTrackWidth,
        other.progressTrackWidth,
        t,
      ),
      maxContentWidth: _lerp(maxContentWidth, other.maxContentWidth, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
