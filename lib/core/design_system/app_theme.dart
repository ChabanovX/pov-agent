import 'package:flutter/cupertino.dart';

import 'package:pov_agent/core/design_system/tokens/tokens.dart';

/// Application-wide iOS Cupertino theme factories.
abstract final class AppTheme {
  /// The dark Cupertino application theme.
  static CupertinoThemeData dark() {
    const colors = AppColors.dark;
    const typography = AppTypography.regular;

    return CupertinoThemeData(
      barBackgroundColor: colors.surface,
      brightness: Brightness.dark,
      primaryColor: colors.actionPrimary,
      primaryContrastingColor: colors.onActionPrimary,
      scaffoldBackgroundColor: colors.background,
      selectionHandleColor: colors.actionPrimary,
      applyThemeToAll: true,
      textTheme: CupertinoTextThemeData(
        actionSmallTextStyle: typography.status.copyWith(
          color: colors.actionPrimary,
        ),
        actionTextStyle: typography.label.copyWith(
          color: colors.actionPrimary,
        ),
        dateTimePickerTextStyle: typography.body.copyWith(
          color: colors.textPrimary,
        ),
        navActionTextStyle: typography.label.copyWith(
          color: colors.actionPrimary,
        ),
        navLargeTitleTextStyle: typography.hero.copyWith(
          color: colors.textPrimary,
        ),
        navTitleTextStyle: typography.headline.copyWith(
          color: colors.textPrimary,
        ),
        pickerTextStyle: typography.body.copyWith(
          color: colors.textPrimary,
        ),
        primaryColor: colors.actionPrimary,
        tabLabelTextStyle: typography.status.copyWith(
          color: colors.textPrimary,
        ),
        textStyle: typography.body.copyWith(color: colors.textPrimary),
      ),
    );
  }

  /// Compatibility factory used by screens awaiting dark-theme migration.
  static CupertinoThemeData light() => dark();
}
