import 'package:flutter/material.dart';

import 'package:pov_agent/core/constants/ui_constants.dart';

/// Semantic spacing values and insets used by application layouts.
@immutable
final class AppSpacing extends ThemeExtension<AppSpacing> {
  /// Creates spacing tokens from the supplied scale.
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.component,
    required this.md,
    required this.lg,
    required this.xl,
  });

  /// The extra-small spacing value in logical pixels.
  final double xs;

  /// The small spacing value in logical pixels.
  final double sm;

  /// The standard component gap in logical pixels.
  final double component;

  /// The medium spacing value in logical pixels.
  final double md;

  /// The large spacing value in logical pixels.
  final double lg;

  /// The extra-large spacing value in logical pixels.
  final double xl;

  /// Equal page insets derived from [md].
  EdgeInsets get page => EdgeInsets.all(md);

  /// Equal small insets derived from [sm].
  EdgeInsets get insetSm => EdgeInsets.all(sm);

  /// Equal component insets derived from [component].
  EdgeInsets get insetComponent => EdgeInsets.all(component);

  /// Equal extra-large insets derived from [xl].
  EdgeInsets get insetXl => EdgeInsets.all(xl);

  /// Equal large insets derived from [lg].
  EdgeInsets get insetLg => EdgeInsets.all(lg);

  /// A start-only inset derived from [sm].
  EdgeInsetsDirectional get startSm => EdgeInsetsDirectional.only(start: sm);

  /// A start-only inset derived from [xs].
  EdgeInsetsDirectional get startXs => EdgeInsetsDirectional.only(start: xs);

  /// A start-only inset derived from [md].
  EdgeInsetsDirectional get startMd => EdgeInsetsDirectional.only(start: md);

  /// A bottom-only inset derived from [md].
  EdgeInsets get bottomMd => EdgeInsets.only(bottom: md);

  /// A bottom-only inset derived from [component].
  EdgeInsets get bottomComponent => EdgeInsets.only(bottom: component);

  /// A top-only inset derived from [xs].
  EdgeInsets get topXs => EdgeInsets.only(top: xs);

  /// A top-only inset derived from [sm].
  EdgeInsets get topSm => EdgeInsets.only(top: sm);

  /// A top-only inset derived from [component].
  EdgeInsets get topComponent => EdgeInsets.only(top: component);

  /// A top-only inset derived from [md].
  EdgeInsets get topMd => EdgeInsets.only(top: md);

  /// A top-only inset derived from [lg].
  EdgeInsets get topLg => EdgeInsets.only(top: lg);

  /// A top-only inset matching camera-overlay content.
  EdgeInsets get topOverlay => const EdgeInsets.only(
    top: kCameraOverlayTopPadding,
  );

  /// Horizontal insets derived from [md].
  EdgeInsets get horizontalMd => EdgeInsets.symmetric(horizontal: md);

  /// Compact control insets using [md] horizontally and [sm] vertically.
  EdgeInsets get compactControl => EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );

  /// Section insets using [md] horizontally and [component] vertically.
  EdgeInsets get section => EdgeInsets.symmetric(
    horizontal: md,
    vertical: component,
  );

  /// Insets for the camera-first overlay content.
  EdgeInsets get cameraOverlay => EdgeInsets.fromLTRB(
    component,
    kCameraOverlayTopPadding,
    component,
    sm,
  );

  /// Insets inside the compact operational status capsule.
  EdgeInsets get statusBadge => const EdgeInsets.symmetric(
    horizontal: kStatusBadgeHorizontalPadding,
    vertical: kStatusBadgeVerticalPadding,
  );

  /// Insets for the microphone rationale content.
  EdgeInsets get microphoneSheet => EdgeInsets.fromLTRB(md, xs, md, md);

  /// Insets for privacy-sheet content.
  EdgeInsets get privacySheet => EdgeInsets.fromLTRB(
    md,
    0,
    md,
    kSheetBottomPadding,
  );

  /// Header insets for session sheets.
  EdgeInsets get sessionSheetHeader => EdgeInsets.fromLTRB(
    md,
    kCameraOverlayTopPadding,
    sm,
    sm,
  );

  /// Header insets for Settings sheets.
  EdgeInsets get settingsSheetHeader => EdgeInsets.fromLTRB(md, sm, sm, sm);

  /// Vertical inset for a key-value diagnostics row.
  EdgeInsets get diagnosticRow => const EdgeInsets.symmetric(
    vertical: kDiagnosticRowVerticalPadding,
  );

  /// Safe-area insets used by the canonical iPhone render viewport.
  EdgeInsets get referencePhoneSafeArea => const EdgeInsets.only(
    top: kReferencePhoneTopInset,
    bottom: kReferencePhoneBottomInset,
  );

  /// The standard application spacing scale.
  static const regular = AppSpacing(
    xs: kSpacingXs,
    sm: kSpacingSm,
    component: kSpacingComponent,
    md: kSpacingMd,
    lg: kSpacingLg,
    xl: kSpacingXl,
  );

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? component,
    double? md,
    double? lg,
    double? xl,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      component: component ?? this.component,
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
      component: _lerp(component, other.component, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
    );
  }
}

double _lerp(double begin, double end, double t) => begin + (end - begin) * t;
