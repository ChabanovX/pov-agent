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

/// The light theme's primary ARGB color value.
const int kColorPrimaryLightValue = 0xFF1C6E5C;

/// The light theme's content-on-primary ARGB color value.
const int kColorOnPrimaryLightValue = 0xFFFFFFFF;

/// The light theme's background ARGB color value.
const int kColorBackgroundLightValue = 0xFFF8FAF9;

/// The light theme's surface ARGB color value.
const int kColorSurfaceLightValue = 0xFFFFFFFF;

/// The light theme's content-on-surface ARGB color value.
const int kColorOnSurfaceLightValue = 0xFF18201D;

/// The light theme's muted-content ARGB color value.
const int kColorMutedLightValue = 0xFF66736F;

/// The light theme's danger ARGB color value.
const int kColorDangerLightValue = 0xFFB3261E;

/// Extra-small spacing in logical pixels.
const double kSpacingXs = 4;

/// Small spacing in logical pixels.
const double kSpacingSm = 8;

/// Medium spacing in logical pixels.
const double kSpacingMd = 16;

/// Large spacing in logical pixels.
const double kSpacingLg = 24;

/// Extra-large spacing in logical pixels.
const double kSpacingXl = 32;

/// Title text size in logical pixels.
const double kFontSizeTitle = 22;

/// Body text size in logical pixels.
const double kFontSizeBody = 16;

/// Label text size in logical pixels.
const double kFontSizeLabel = 14;

/// Small corner radius in logical pixels.
const double kRadiusSm = 4;

/// Medium corner radius in logical pixels.
const double kRadiusMd = 8;

/// Large corner radius in logical pixels.
const double kRadiusLg = 12;

/// Standard icon size in logical pixels.
const double kIconSize = 24;

/// Hero icon size in logical pixels.
const double kHeroIconSize = 40;

/// Standard interactive-control height in logical pixels.
const double kControlHeight = 48;

/// Model-download progress track width in logical pixels.
const double kProgressTrackWidth = 240;

/// Maximum readable content width in logical pixels.
const double kMaxContentWidth = 720;

/// The level-one shadow ARGB color value.
const int kShadowLevel1ColorValue = 0x1F000000;

/// The level-one shadow blur radius in logical pixels.
const double kShadowLevel1BlurRadius = 16;

/// The level-one shadow horizontal offset in logical pixels.
const double kShadowLevel1OffsetX = 0;

/// The level-one shadow vertical offset in logical pixels.
const double kShadowLevel1OffsetY = 8;

/// The duration for immediate UI transitions.
const Duration kAnimationFast = Duration(milliseconds: 120);

/// The duration for standard UI transitions.
const Duration kAnimationNormal = Duration(milliseconds: 220);

/// The duration for emphasized UI transitions.
const Duration kAnimationSlow = Duration(milliseconds: 360);
