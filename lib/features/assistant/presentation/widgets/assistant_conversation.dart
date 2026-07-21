import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_model_status.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/hands_free_agent_panel.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/observer_session_panel.dart';

/// Renders committed dialogue plus the active, uncommitted generation draft.
final class AssistantConversation extends StatelessWidget {
  /// Creates a session transcript from [state].
  const AssistantConversation({
    required this.state,
    required this.scrollController,
    required this.onRetryAnswer,
    required this.onModelRetry,
    required this.onVoiceRetry,
    required this.onIntervalSelected,
    required this.onObservationStart,
    required this.onObservationStop,
    required this.onSpeechMutedChanged,
    required this.onCommentReplay,
    required this.onSpeechStop,
    super.key,
  });

  /// The committed messages and optional generation draft to render.
  final ObserverState state;

  /// Controls transcript scrolling and is owned by the page.
  final ScrollController scrollController;

  /// Retries the failed uncommitted turn.
  final VoidCallback onRetryAnswer;

  /// Retries a recoverable model preparation failure.
  final VoidCallback onModelRetry;

  /// Retries recoverable hands-free model, permission, or input setup.
  final VoidCallback onVoiceRetry;

  /// Replaces the session-only automatic cadence.
  final ValueChanged<ObserverInterval> onIntervalSelected;

  /// Enables periodic automatic comments.
  final VoidCallback onObservationStart;

  /// Disables periodic comments and cancels automatic generation.
  final VoidCallback onObservationStop;

  /// Changes whether future completed comments may be spoken automatically.
  final ValueChanged<bool> onSpeechMutedChanged;

  /// Replays the committed comment at an append-only transcript index.
  final ValueChanged<int> onCommentReplay;

  /// Stops the comment currently being spoken.
  final VoidCallback onSpeechStop;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final children = <Widget>[
      HandsFreeAgentPanel(
        state: state,
        onRetry: onVoiceRetry,
      ),
      Padding(
        padding: AppSpacing.regular.topMd,
        child: ObserverSessionPanel(
          state: state,
          onIntervalSelected: onIntervalSelected,
          onStart: onObservationStart,
          onStop: onObservationStop,
          onSpeechMutedChanged: onSpeechMutedChanged,
          onCommentReplay: onCommentReplay,
          onSpeechStop: onSpeechStop,
        ),
      ),
      if (state.modelStatus != ObserverModelStatus.ready) AssistantModelStatusView(state: state, onRetry: onModelRetry),
      if (state.modelStatus == ObserverModelStatus.ready && state.messages.isEmpty && state.manualDraftPrompt.isEmpty)
        const _AssistantEmptyState(),
      for (final message in state.messages)
        _MessageBubble(
          role: message.role,
          content: message.content,
        ),
      if (state.manualDraftPrompt.isNotEmpty)
        _MessageBubble(
          role: ConversationRole.user,
          content: state.manualDraftPrompt,
        ),
      if (state.manualDraftResponse.isNotEmpty || state.activeGeneration == ObserverGenerationKind.manual)
        _DraftResponseBubble(
          content: state.manualDraftResponse,
        ),
      if (state.manualFailure != null)
        _GenerationFailure(
          onRetry: onRetryAnswer,
        ),
    ];

    return Semantics(
      container: true,
      label: localizations.assistantConversationLabel,
      child: SingleChildScrollView(
        key: assistantConversationKey,
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: AppSpacing.regular.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

final class _AssistantEmptyState extends StatelessWidget {
  const _AssistantEmptyState();

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const sizes = AppSizes.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: spacing.page,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.sparkles,
            color: colors.primary,
            size: sizes.heroIcon,
          ),
          Padding(
            padding: spacing.topMd,
            child: Text(
              localizations.assistantReadyTitle,
              style: typography.title.copyWith(color: colors.onSurface),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: spacing.topMd,
            child: Text(
              localizations.assistantReadyMessage,
              style: typography.body.copyWith(color: colors.muted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
  });

  final ConversationRole role;
  final String content;

  @override
  Widget build(BuildContext context) {
    final user = role == ConversationRole.user;
    return _BubbleLayout(
      role: role,
      child: _BubbleSurface(
        user: user,
        child: Text(content),
      ),
    );
  }
}

final class _DraftResponseBubble extends StatelessWidget {
  const _DraftResponseBubble({
    required this.content,
  });

  final String content;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    const colors = AppColors.light;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return _BubbleLayout(
      role: ConversationRole.assistant,
      child: _BubbleSurface(
        user: false,
        child: content.isNotEmpty
            ? Text(content)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(radius: spacing.sm),
                  Padding(
                    padding: spacing.startSm,
                    child: Text(
                      localizations.assistantThinkingMessage,
                      style: typography.body.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

final class _BubbleLayout extends StatelessWidget {
  const _BubbleLayout({
    required this.role,
    required this.child,
  });

  final ConversationRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    const colors = AppColors.light;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final user = role == ConversationRole.user;

    return Padding(
      padding: spacing.bottomMd,
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.84,
          child: Column(
            crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                user ? localizations.assistantUserRoleLabel : localizations.assistantRoleLabel,
                style: typography.label.copyWith(color: colors.muted),
              ),
              Padding(
                padding: spacing.topXs,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _BubbleSurface extends StatelessWidget {
  const _BubbleSurface({
    required this.user,
    required this.child,
  });

  final bool user;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const typography = AppTypography.regular;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: user ? colors.primary : colors.surface,
        border: user ? null : Border.all(color: colors.muted.withValues(alpha: 0.2)),
        borderRadius: radius.lg,
      ),
      child: Padding(
        padding: spacing.section,
        child: DefaultTextStyle(
          style: typography.body.copyWith(
            color: user ? colors.onPrimary : colors.onSurface,
          ),
          child: child,
        ),
      ),
    );
  }
}

final class _GenerationFailure extends StatelessWidget {
  const _GenerationFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const radius = AppRadius.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.08),
          borderRadius: radius.md,
        ),
        child: Padding(
          padding: spacing.section,
          child: Row(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                color: colors.danger,
              ),
              Expanded(
                child: Padding(
                  padding: spacing.horizontalMd,
                  child: Text(
                    localizations.assistantGenerationFailureMessage,
                    style: typography.body.copyWith(color: colors.onSurface),
                  ),
                ),
              ),
              CupertinoButton(
                key: assistantAnswerRetryButtonKey,
                padding: EdgeInsets.zero,
                onPressed: onRetry,
                child: Text(localizations.assistantRetryAnswerAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
