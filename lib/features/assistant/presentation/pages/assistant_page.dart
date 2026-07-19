import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_composer.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_conversation.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_model_status.dart';

/// The manual, session-only on-device assistant tab.
///
/// Model preparation is started by app routing on first tab selection. This
/// page owns only editable and scroll controllers; all model and generation
/// effects enter through [AssistantBloc] events.
final class AssistantPage extends StatefulWidget {
  /// Creates the assistant page.
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

final class _AssistantPageState extends State<AssistantPage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(localizations.assistantTabLabel),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppSizes.regular.maxContentWidth,
            ),
            child: BlocListener<AssistantBloc, AssistantState>(
              listenWhen: _transcriptChanged,
              listener: (_, _) => _scheduleScrollToLatest(),
              child: BlocBuilder<AssistantBloc, AssistantState>(
                builder: (context, state) {
                  if (state.modelStatus != AssistantModelStatus.ready) {
                    return AssistantModelStatusView(
                      state: state,
                      onRetry: () {
                        context.read<AssistantBloc>().add(
                          const AssistantModelRetryRequested(),
                        );
                      },
                    );
                  }

                  final generating = state.generationStatus == AssistantGenerationStatus.generating;
                  return Column(
                    children: [
                      Expanded(
                        child: AssistantConversation(
                          state: state,
                          scrollController: _scrollController,
                          onRetryAnswer: () {
                            context.read<AssistantBloc>().add(
                              const AssistantAnswerRetryRequested(),
                            );
                          },
                        ),
                      ),
                      AssistantComposer(
                        controller: _promptController,
                        generating: generating,
                        canSubmit: state.canSubmit,
                        onSend: _submitPrompt,
                        onStop: () {
                          context.read<AssistantBloc>().add(
                            const AssistantGenerationCancelled(),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submitPrompt() {
    final bloc = context.read<AssistantBloc>();
    final prompt = _promptController.text.trim();
    if (!bloc.state.canSubmit || prompt.isEmpty) return;

    bloc.add(AssistantPromptSubmitted(prompt));
    _promptController.clear();
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppAnimations.regular.normal,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  static bool _transcriptChanged(
    AssistantState previous,
    AssistantState current,
  ) {
    return previous.messages.length != current.messages.length ||
        previous.draftPrompt != current.draftPrompt ||
        previous.draftResponse != current.draftResponse ||
        previous.generationStatus != current.generationStatus;
  }
}
