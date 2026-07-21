import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic component dimensions used throughout the application.
@immutable
final class AppSizes extends ThemeExtension<AppSizes> {
  /// Creates component-size tokens from the supplied dimensions.
  const AppSizes({
    required this.icon,
    required this.heroIcon,
    required this.controlHeight,
    required this.primaryActionHeight,
    required this.tabBarHeight,
    required this.statusBadgeHeight,
    required this.detectionStrokeWidth,
    required this.progressTrackWidth,
    required this.maxContentWidth,
    required this.cameraContextMaxWidth,
    required this.sheetIcon,
    required this.sheetGrabberWidth,
    required this.sheetGrabberHeight,
    required this.hairlineWidth,
  });

  /// The standard icon size in logical pixels.
  final double icon;

  /// The hero icon size in logical pixels.
  final double heroIcon;

  /// The standard interactive-control height in logical pixels.
  final double controlHeight;

  /// The primary iOS action height in logical pixels.
  final double primaryActionHeight;

  /// The standard iOS Tab Bar content height before its safe-area inset.
  final double tabBarHeight;

  /// The minimum status-badge height in logical pixels.
  final double statusBadgeHeight;

  /// The live detection-box stroke width in logical pixels.
  final double detectionStrokeWidth;

  /// The model-download progress track width in logical pixels.
  final double progressTrackWidth;

  /// The maximum readable content width in logical pixels.
  final double maxContentWidth;

  /// The maximum width of a contextual camera rationale.
  final double cameraContextMaxWidth;

  /// The icon size used in modal rationales and runtime errors.
  final double sheetIcon;

  /// The native-style modal-sheet drag-indicator width.
  final double sheetGrabberWidth;

  /// The native-style modal-sheet drag-indicator height.
  final double sheetGrabberHeight;

  /// The semantic hairline border width.
  final double hairlineWidth;

  /// The standard application component dimensions.
  static const regular = AppSizes(
    icon: kIconSize,
    heroIcon: kHeroIconSize,
    controlHeight: kControlHeight,
    primaryActionHeight: kPrimaryActionHeight,
    tabBarHeight: kTabBarHeight,
    statusBadgeHeight: kStatusBadgeHeight,
    detectionStrokeWidth: kDetectionStrokeWidth,
    progressTrackWidth: kProgressTrackWidth,
    maxContentWidth: kMaxContentWidth,
    cameraContextMaxWidth: kCameraContextMaxWidth,
    sheetIcon: kSheetIconSize,
    sheetGrabberWidth: kSheetGrabberWidth,
    sheetGrabberHeight: kSheetGrabberHeight,
    hairlineWidth: kHairlineWidth,
  );

  @override
  AppSizes copyWith({
    double? icon,
    double? heroIcon,
    double? controlHeight,
    double? primaryActionHeight,
    double? tabBarHeight,
    double? statusBadgeHeight,
    double? detectionStrokeWidth,
    double? progressTrackWidth,
    double? maxContentWidth,
    double? cameraContextMaxWidth,
    double? sheetIcon,
    double? sheetGrabberWidth,
    double? sheetGrabberHeight,
    double? hairlineWidth,
  }) {
    return AppSizes(
      icon: icon ?? this.icon,
      heroIcon: heroIcon ?? this.heroIcon,
      controlHeight: controlHeight ?? this.controlHeight,
      primaryActionHeight: primaryActionHeight ?? this.primaryActionHeight,
      tabBarHeight: tabBarHeight ?? this.tabBarHeight,
      statusBadgeHeight: statusBadgeHeight ?? this.statusBadgeHeight,
      detectionStrokeWidth: detectionStrokeWidth ?? this.detectionStrokeWidth,
      progressTrackWidth: progressTrackWidth ?? this.progressTrackWidth,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
      cameraContextMaxWidth: cameraContextMaxWidth ?? this.cameraContextMaxWidth,
      sheetIcon: sheetIcon ?? this.sheetIcon,
      sheetGrabberWidth: sheetGrabberWidth ?? this.sheetGrabberWidth,
      sheetGrabberHeight: sheetGrabberHeight ?? this.sheetGrabberHeight,
      hairlineWidth: hairlineWidth ?? this.hairlineWidth,
    );
  }

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    return AppSizes(
      icon: _lerp(icon, other.icon, t),
      heroIcon: _lerp(heroIcon, other.heroIcon, t),
      controlHeight: _lerp(controlHeight, other.controlHeight, t),
      primaryActionHeight: _lerp(
        primaryActionHeight,
        other.primaryActionHeight,
        t,
      ),
      tabBarHeight: _lerp(tabBarHeight, other.tabBarHeight, t),
      statusBadgeHeight: _lerp(
        statusBadgeHeight,
        other.statusBadgeHeight,
        t,
      ),
      detectionStrokeWidth: _lerp(
        detectionStrokeWidth,
        other.detectionStrokeWidth,
        t,
      ),
      progressTrackWidth: _lerp(
        progressTrackWidth,
        other.progressTrackWidth,
        t,
      ),
      maxContentWidth: _lerp(maxContentWidth, other.maxContentWidth, t),
      cameraContextMaxWidth: _lerp(
        cameraContextMaxWidth,
        other.cameraContextMaxWidth,
        t,
      ),
      sheetIcon: _lerp(sheetIcon, other.sheetIcon, t),
      sheetGrabberWidth: _lerp(
        sheetGrabberWidth,
        other.sheetGrabberWidth,
        t,
      ),
      sheetGrabberHeight: _lerp(
        sheetGrabberHeight,
        other.sheetGrabberHeight,
        t,
      ),
      hairlineWidth: _lerp(hairlineWidth, other.hairlineWidth, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
