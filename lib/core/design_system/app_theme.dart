import 'package:flutter/cupertino.dart';

import 'package:pov_agent/core/design_system/tokens/tokens.dart';

/// Application-wide Cupertino theme factories.
abstract final class AppTheme {
  /// The light Cupertino application theme.
  static CupertinoThemeData light() {
    const colors = AppColors.light;
    const typography = AppTypography.regular;

    return CupertinoThemeData(
      barBackgroundColor: colors.surface,
      brightness: Brightness.light,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.background,
      textTheme: CupertinoTextThemeData(
        actionTextStyle: typography.label.copyWith(color: colors.primary),
        navTitleTextStyle: typography.title.copyWith(color: colors.onSurface),
        primaryColor: colors.primary,
        tabLabelTextStyle: typography.label.copyWith(color: colors.onSurface),
        textStyle: typography.body.copyWith(color: colors.onSurface),
      ),
    );
  }
}
