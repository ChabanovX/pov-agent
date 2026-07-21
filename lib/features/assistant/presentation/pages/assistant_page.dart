import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_composer.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/assistant_conversation.dart';

/// The continuous observer and manual, session-only on-device assistant tab.
///
/// Process startup owns model and timer activation. This page owns only
/// editable and scroll controllers; all effects enter through [ObserverBloc]
/// events.
final class AssistantPage extends StatefulWidget {
  /// Creates the assistant page.
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

final class _AssistantPageState extends State<AssistantPage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _submittedPrompt;

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
            child: BlocListener<ObserverBloc, ObserverState>(
              listenWhen: _transcriptChanged,
              listener: (_, state) {
                _clearAcceptedPrompt(state);
                _scheduleScrollToLatest();
              },
              child: BlocBuilder<ObserverBloc, ObserverState>(
                builder: (context, state) {
                  final manualGenerating = state.activeGeneration == ObserverGenerationKind.manual;
                  return Column(
                    children: [
                      Expanded(
                        child: AssistantConversation(
                          state: state,
                          scrollController: _scrollController,
                          onRetryAnswer: () {
                            context.read<ObserverBloc>().add(
                              const ObserverAnswerRetryRequested(),
                            );
                          },
                          onModelRetry: () {
                            context.read<ObserverBloc>().add(
                              const ObserverModelRetryRequested(),
                            );
                          },
                          onIntervalSelected: (interval) {
                            context.read<ObserverBloc>().add(
                              ObservationIntervalSelected(interval),
                            );
                          },
                          onObservationStart: () {
                            context.read<ObserverBloc>().add(
                              const ObservationStarted(),
                            );
                          },
                          onObservationStop: () {
                            context.read<ObserverBloc>().add(
                              const ObservationStopped(),
                            );
                          },
                          onSpeechMutedChanged: (muted) {
                            context.read<ObserverBloc>().add(
                              ObserverSpeechMutedChanged(muted: muted),
                            );
                          },
                          onCommentReplay: (commentIndex) {
                            context.read<ObserverBloc>().add(
                              ObserverCommentReplayRequested(commentIndex),
                            );
                          },
                          onSpeechStop: () {
                            context.read<ObserverBloc>().add(
                              const ObserverSpeechStopped(),
                            );
                          },
                        ),
                      ),
                      if (state.modelStatus == ObserverModelStatus.ready)
                        AssistantComposer(
                          controller: _promptController,
                          generating: manualGenerating,
                          canSubmit: state.canSubmit,
                          onSend: _submitPrompt,
                          onStop: () {
                            context.read<ObserverBloc>().add(
                              const ObserverManualGenerationCancelled(),
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
    final bloc = context.read<ObserverBloc>();
    final prompt = _promptController.text.trim();
    if (!bloc.state.canSubmit || prompt.isEmpty) return;

    // Keep editable text until the Bloc has crossed any speech-preemption
    // barrier and projected the accepted manual request.
    _submittedPrompt = prompt;
    bloc.add(ObserverPromptSubmitted(prompt));
  }

  void _clearAcceptedPrompt(ObserverState state) {
    final submittedPrompt = _submittedPrompt;
    if (submittedPrompt == null ||
        state.activeGeneration != ObserverGenerationKind.manual ||
        state.manualDraftPrompt != submittedPrompt) {
      return;
    }

    _submittedPrompt = null;
    if (_promptController.text.trim() == submittedPrompt) {
      _promptController.clear();
    }
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
    ObserverState previous,
    ObserverState current,
  ) {
    return previous.messages.length != current.messages.length ||
        previous.comments.length != current.comments.length ||
        previous.manualDraftPrompt != current.manualDraftPrompt ||
        previous.manualDraftResponse != current.manualDraftResponse ||
        previous.automaticDraft != current.automaticDraft ||
        previous.activeGeneration != current.activeGeneration;
  }
}
