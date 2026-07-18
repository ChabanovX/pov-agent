import 'package:flutter/material.dart';

import 'package:some_camera_with_llm/core/constants/ui_constants.dart';

/// Semantic text styles used throughout the application.
@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  /// Creates typography tokens from the supplied semantic styles.
  const AppTypography({
    required this.title,
    required this.body,
    required this.label,
  });

  /// The style for page and section titles.
  final TextStyle title;

  /// The style for primary body content.
  final TextStyle body;

  /// The style for controls and compact labels.
  final TextStyle label;

  /// The standard application typography.
  static const regular = AppTypography(
    title: TextStyle(
      fontSize: kFontSizeTitle,
      fontWeight: FontWeight.w600,
    ),
    body: TextStyle(
      fontSize: kFontSizeBody,
      fontWeight: FontWeight.w400,
    ),
    label: TextStyle(
      fontSize: kFontSizeLabel,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  AppTypography copyWith({
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
  }) {
    return AppTypography(
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
    );
  }
}
