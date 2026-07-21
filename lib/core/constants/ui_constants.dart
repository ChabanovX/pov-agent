/// Shared UI primitive constants.
///
/// Theme extensions compose these values into semantic tokens. Constants that
/// are only meaningful inside one file should stay private in that file.
library;

import 'package:flutter/foundation.dart';

/// Stable key for the assistant prompt field.
const assistantPromptFieldKey = Key('assistant-prompt-field');

/// Stable key for the assistant send-or-stop control.
const assistantSubmitControlKey = Key('assistant-submit-control');

/// Stable key for the scrollable assistant transcript.
const assistantConversationKey = Key('assistant-conversation');

/// Stable key for retrying the latest failed assistant answer.
const assistantAnswerRetryButtonKey = Key('assistant-answer-retry-button');

/// Stable key for retrying local-model preparation.
const assistantModelRetryButtonKey = Key('assistant-model-retry-button');

/// Stable key for the hands-free agent status surface.
const handsFreeAgentPanelKey = Key('hands-free-agent-panel');

/// Stable key for retrying hands-free model, permission, or input setup.
const handsFreeAgentRetryButtonKey = Key('hands-free-agent-retry-button');

/// Stable key for the automatic observer start-or-stop control.
const observerToggleButtonKey = Key('observer-toggle-button');

/// Stable key for the session-only observation interval control.
const observerIntervalControlKey = Key('observer-interval-control');

/// Stable key for the latest stable-scene object summary.
const observerSceneKey = Key('observer-scene');

/// Stable key for the automatic observation transcript.
const observerTranscriptKey = Key('observer-transcript');

/// Stable key for the session-wide speech mute control.
const observerSpeechMuteButtonKey = Key('observer-speech-mute-button');

/// Returns the stable speech control key for a committed observer comment.
Key observerCommentSpeechButtonKey(int commentIndex) => Key('observer-comment-speech-$commentIndex');

/// The application canvas ARGB color value.
const int kColorBackgroundValue = 0xFF000000;

/// The grouped-surface ARGB color value.
const int kColorSurfaceValue = 0xFF111111;

/// The raised-surface ARGB color value.
const int kColorSurfaceRaisedValue = 0xFF1B1B1B;

/// The strong camera-overlay ARGB color value.
const int kColorOverlayStrongValue = 0xC7000000;

/// The soft camera-overlay ARGB color value.
const int kColorOverlaySoftValue = 0x85000000;

/// The top camera scrim ARGB color value.
const int kColorCameraScrimTopValue = 0xB8000000;

/// The transparent camera scrim ARGB color value.
const int kColorCameraScrimClearValue = 0x00000000;

/// The middle camera scrim ARGB color value.
const int kColorCameraScrimMiddleValue = 0x18000000;

/// The bottom camera scrim ARGB color value.
const int kColorCameraScrimBottomValue = 0xD8000000;

/// The primary text and icon ARGB color value.
const int kColorTextPrimaryValue = 0xFFFFFFFF;

/// The secondary text and icon ARGB color value.
const int kColorTextSecondaryValue = 0xFFB8B8B8;

/// The divider and inactive-outline ARGB color value.
const int kColorBorderValue = 0xFF343434;

/// The primary-action ARGB color value.
const int kColorActionPrimaryValue = 0xFFFFFFFF;

/// The content-on-primary-action ARGB color value.
const int kColorOnActionPrimaryValue = 0xFF000000;

/// The ready and watching ARGB color value.
const int kColorSuccessValue = 0xFF58E07B;

/// The wake-detected and listening ARGB color value.
const int kColorListeningValue = 0xFF70A7FF;

/// The recoverable-warning ARGB color value.
const int kColorWarningValue = 0xFFFFC857;

/// The critical and destructive ARGB color value.
const int kColorDangerValue = 0xFFFF6666;

/// Compatibility name for the primary-action color.
const int kColorPrimaryLightValue = kColorActionPrimaryValue;

/// Compatibility name for the legacy light overlay foreground.
const int kColorOnPrimaryLightValue = kColorTextPrimaryValue;

/// Compatibility name for the application canvas.
const int kColorBackgroundLightValue = kColorBackgroundValue;

/// Compatibility name for the grouped surface.
const int kColorSurfaceLightValue = kColorSurfaceValue;

/// Compatibility name for primary text and icons.
const int kColorOnSurfaceLightValue = kColorTextPrimaryValue;

/// Compatibility name for secondary text and icons.
const int kColorMutedLightValue = kColorTextSecondaryValue;

/// Compatibility name for the critical and destructive color.
const int kColorDangerLightValue = kColorDangerValue;

/// Extra-small spacing in logical pixels.
const double kSpacingXs = 4;

/// Small spacing in logical pixels.
const double kSpacingSm = 8;

/// Component spacing in logical pixels.
const double kSpacingComponent = 12;

/// Medium spacing in logical pixels.
const double kSpacingMd = 16;

/// Large spacing in logical pixels.
const double kSpacingLg = 24;

/// Extra-large spacing in logical pixels.
const double kSpacingXl = 32;

/// Top inset for camera-overlay content in logical pixels.
const double kCameraOverlayTopPadding = 10;

/// Horizontal status-badge inset in logical pixels.
const double kStatusBadgeHorizontalPadding = 11;

/// Vertical status-badge inset in logical pixels.
const double kStatusBadgeVerticalPadding = 5;

/// Bottom inset for modal-sheet content in logical pixels.
const double kSheetBottomPadding = 20;

/// Vertical inset for a diagnostics row in logical pixels.
const double kDiagnosticRowVerticalPadding = 9;

/// Top safe-area inset of the canonical iPhone design viewport.
const double kReferencePhoneTopInset = 47;

/// Bottom safe-area inset of the canonical iPhone design viewport.
const double kReferencePhoneBottomInset = 34;

/// Setup-hero text size in logical pixels.
const double kFontSizeHero = 34;

/// Setup-hero line height in logical pixels.
const double kLineHeightHero = 41;

/// Screen and modal-title text size in logical pixels.
const double kFontSizeTitle = 22;

/// Screen and modal-title line height in logical pixels.
const double kLineHeightTitle = 28;

/// Section-emphasis text size in logical pixels.
const double kFontSizeHeadline = 17;

/// Section-emphasis line height in logical pixels.
const double kLineHeightHeadline = 22;

/// Body text size in logical pixels.
const double kFontSizeBody = 17;

/// Body line height in logical pixels.
const double kLineHeightBody = 22;

/// Control-label text size in logical pixels.
const double kFontSizeLabel = 15;

/// Control-label line height in logical pixels.
const double kLineHeightLabel = 20;

/// Status and chip text size in logical pixels.
const double kFontSizeStatus = 12;

/// Status and chip line height in logical pixels.
const double kLineHeightStatus = 16;

/// Metadata text size in logical pixels.
const double kFontSizeMetadata = 13;

/// Metadata line height in logical pixels.
const double kLineHeightMetadata = 18;

/// Compact overlay and control radius in logical pixels.
const double kRadiusSm = 12;

/// Compatibility radius for compact overlays in logical pixels.
const double kRadiusMd = 12;

/// Assistant and model-card radius in logical pixels.
const double kRadiusLg = 16;

/// Primary-action radius in logical pixels.
const double kRadiusAction = 14;

/// Fully rounded capsule radius in logical pixels.
const double kRadiusFull = 999;

/// Top corner radius for native-style modal sheets in logical pixels.
const double kRadiusSheet = 20;

/// Standard icon size in logical pixels.
const double kIconSize = 24;

/// Hero icon size in logical pixels.
const double kHeroIconSize = 40;

/// Minimum iOS interactive-control height in logical pixels.
const double kControlHeight = 44;

/// Primary iOS action height in logical pixels.
const double kPrimaryActionHeight = 50;

/// Standard iOS Tab Bar content height in logical pixels.
const double kTabBarHeight = 49;

/// Minimum iOS status-badge height in logical pixels.
const double kStatusBadgeHeight = 28;

/// Live detection stroke width in logical pixels.
const double kDetectionStrokeWidth = 2;

/// Model-download progress track width in logical pixels.
const double kProgressTrackWidth = 240;

/// Maximum readable content width in logical pixels.
const double kMaxContentWidth = 720;

/// Maximum camera-rationale card width in logical pixels.
const double kCameraContextMaxWidth = 340;

/// Modal rationale and runtime-error icon size in logical pixels.
const double kSheetIconSize = 30;

/// Modal-sheet drag-indicator width in logical pixels.
const double kSheetGrabberWidth = 38;

/// Modal-sheet drag-indicator height in logical pixels.
const double kSheetGrabberHeight = 5;

/// One physical-pixel-style semantic border width in logical pixels.
const double kHairlineWidth = 0.5;

/// The restrained level-one shadow ARGB color value.
const int kShadowLevel1ColorValue = 0x33000000;

/// The level-one shadow blur radius in logical pixels.
const double kShadowLevel1BlurRadius = 8;

/// The level-one shadow horizontal offset in logical pixels.
const double kShadowLevel1OffsetX = 0;

/// The level-one shadow vertical offset in logical pixels.
const double kShadowLevel1OffsetY = 2;

/// The duration for immediate UI transitions.
const Duration kAnimationFast = Duration(milliseconds: 120);

/// The duration for standard UI transitions.
const Duration kAnimationNormal = Duration(milliseconds: 200);

/// The duration for emphasized UI transitions.
const Duration kAnimationSlow = Duration(milliseconds: 250);
