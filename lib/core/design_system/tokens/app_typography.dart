import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic iOS text styles used throughout the application.
@immutable
final class AppTypography extends ThemeExtension<AppTypography> {
  /// Creates typography tokens from the supplied semantic styles.
  const AppTypography({
    required this.hero,
    required this.title,
    required this.headline,
    required this.body,
    required this.label,
    required this.status,
    required this.metadata,
  });

  /// The style for the model-setup hero.
  final TextStyle hero;

  /// The style for screen and modal titles.
  final TextStyle title;

  /// The style for section and Assistant emphasis.
  final TextStyle headline;

  /// The style for primary body content.
  final TextStyle body;

  /// The style for control labels.
  final TextStyle label;

  /// The style for status badges and chips.
  final TextStyle status;

  /// The style for diagnostics and secondary metadata.
  final TextStyle metadata;

  /// The standard application typography.
  static const regular = AppTypography(
    hero: TextStyle(
      fontSize: kFontSizeHero,
      fontWeight: FontWeight.w700,
      height: kLineHeightHero / kFontSizeHero,
    ),
    title: TextStyle(
      fontSize: kFontSizeTitle,
      fontWeight: FontWeight.w700,
      height: kLineHeightTitle / kFontSizeTitle,
    ),
    headline: TextStyle(
      fontSize: kFontSizeHeadline,
      fontWeight: FontWeight.w600,
      height: kLineHeightHeadline / kFontSizeHeadline,
    ),
    body: TextStyle(
      fontSize: kFontSizeBody,
      fontWeight: FontWeight.w400,
      height: kLineHeightBody / kFontSizeBody,
    ),
    label: TextStyle(
      fontSize: kFontSizeLabel,
      fontWeight: FontWeight.w600,
      height: kLineHeightLabel / kFontSizeLabel,
    ),
    status: TextStyle(
      fontSize: kFontSizeStatus,
      fontWeight: FontWeight.w600,
      height: kLineHeightStatus / kFontSizeStatus,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    metadata: TextStyle(
      fontSize: kFontSizeMetadata,
      fontWeight: FontWeight.w400,
      height: kLineHeightMetadata / kFontSizeMetadata,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  @override
  AppTypography copyWith({
    TextStyle? hero,
    TextStyle? title,
    TextStyle? headline,
    TextStyle? body,
    TextStyle? label,
    TextStyle? status,
    TextStyle? metadata,
  }) {
    return AppTypography(
      hero: hero ?? this.hero,
      title: title ?? this.title,
      headline: headline ?? this.headline,
      body: body ?? this.body,
      label: label ?? this.label,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      hero: TextStyle.lerp(hero, other.hero, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      headline: TextStyle.lerp(headline, other.headline, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      status: TextStyle.lerp(status, other.status, t)!,
      metadata: TextStyle.lerp(metadata, other.metadata, t)!,
    );
  }
}
