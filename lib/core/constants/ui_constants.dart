/// Shared UI primitive constants.
///
/// Theme extensions compose these values into semantic tokens. Constants that
/// are only meaningful inside one file should stay private in that file.
library;

const int kColorPrimaryLightValue = 0xFF1C6E5C;
const int kColorOnPrimaryLightValue = 0xFFFFFFFF;
const int kColorBackgroundLightValue = 0xFFF8FAF9;
const int kColorSurfaceLightValue = 0xFFFFFFFF;
const int kColorOnSurfaceLightValue = 0xFF18201D;
const int kColorMutedLightValue = 0xFF66736F;
const int kColorDangerLightValue = 0xFFB3261E;

const double kSpacingXs = 4;
const double kSpacingSm = 8;
const double kSpacingMd = 16;
const double kSpacingLg = 24;
const double kSpacingXl = 32;

const double kFontSizeTitle = 22;
const double kFontSizeBody = 16;
const double kFontSizeLabel = 14;

const double kRadiusSm = 4;
const double kRadiusMd = 8;
const double kRadiusLg = 12;

const double kIconSize = 24;
const double kControlHeight = 48;
const double kMaxContentWidth = 720;

const int kShadowLevel1ColorValue = 0x1F000000;
const double kShadowLevel1BlurRadius = 16;
const double kShadowLevel1OffsetX = 0;
const double kShadowLevel1OffsetY = 8;

const Duration kAnimationFast = Duration(milliseconds: 120);
const Duration kAnimationNormal = Duration(milliseconds: 220);
const Duration kAnimationSlow = Duration(milliseconds: 360);
