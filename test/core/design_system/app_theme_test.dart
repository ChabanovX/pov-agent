import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';

void main() {
  test('dark palette matches the product semantic colors', () {
    const colors = AppColors.dark;

    expect(colors.background, const Color(0xFF000000));
    expect(colors.surface, const Color(0xFF111111));
    expect(colors.surfaceRaised, const Color(0xFF1B1B1B));
    expect(colors.overlayStrong, const Color(0xC7000000));
    expect(colors.overlaySoft, const Color(0x85000000));
    expect(colors.textPrimary, const Color(0xFFFFFFFF));
    expect(colors.textSecondary, const Color(0xFFB8B8B8));
    expect(colors.border, const Color(0xFF343434));
    expect(colors.actionPrimary, const Color(0xFFFFFFFF));
    expect(colors.onActionPrimary, const Color(0xFF000000));
    expect(colors.onPrimary, const Color(0xFFFFFFFF));
    expect(colors.success, const Color(0xFF58E07B));
    expect(colors.listening, const Color(0xFF70A7FF));
    expect(colors.warning, const Color(0xFFFFC857));
    expect(colors.danger, const Color(0xFFFF6666));
    expect(AppColors.light.background, AppColors.dark.background);
    expect(AppColors.light.textPrimary, AppColors.dark.textPrimary);
  });

  test('iOS layout and typography tokens match the design scale', () {
    const spacing = AppSpacing.regular;
    const sizes = AppSizes.regular;
    const radius = AppRadius.regular;
    const typography = AppTypography.regular;

    expect(
      [spacing.xs, spacing.sm, spacing.component, spacing.md, spacing.lg, spacing.xl],
      [4, 8, 12, 16, 24, 32],
    );
    expect(spacing.page, const EdgeInsets.all(16));
    expect(
      spacing.section,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    expect(sizes.controlHeight, 44);
    expect(sizes.primaryActionHeight, 50);
    expect(sizes.tabBarHeight, 49);
    expect(sizes.statusBadgeHeight, 28);
    expect(sizes.detectionStrokeWidth, 2);
    expect(radius.compact.topLeft.x, 12);
    expect(radius.card.topLeft.x, 16);
    expect(radius.full.topLeft.x, 999);
    expect(typography.hero.fontSize, 34);
    expect(typography.title.fontSize, 22);
    expect(typography.headline.fontSize, 17);
    expect(typography.body.fontSize, 17);
    expect(typography.label.fontSize, 15);
    expect(typography.status.fontSize, 12);
    expect(typography.metadata.fontSize, 13);
    expect(typography.hero.height, closeTo(41 / 34, 0.0001));
    expect(typography.body.height, closeTo(22 / 17, 0.0001));
  });

  test('theme factories project the dark iOS foundation', () {
    final theme = AppTheme.dark();
    final compatibilityTheme = AppTheme.light();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.dark.background);
    expect(theme.barBackgroundColor, AppColors.dark.surface);
    expect(theme.primaryColor, AppColors.dark.actionPrimary);
    expect(theme.primaryContrastingColor, AppColors.dark.onActionPrimary);
    expect(theme.selectionHandleColor, AppColors.dark.actionPrimary);
    expect(theme.applyThemeToAll, isTrue);
    expect(theme.textTheme.textStyle.color, AppColors.dark.textPrimary);
    expect(theme.textTheme.navLargeTitleTextStyle.fontSize, 34);
    expect(theme.textTheme.navTitleTextStyle.fontSize, 17);
    expect(compatibilityTheme.brightness, Brightness.dark);
    expect(
      compatibilityTheme.scaffoldBackgroundColor,
      theme.scaffoldBackgroundColor,
    );
  });
}
