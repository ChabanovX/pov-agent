import 'package:flutter/cupertino.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';

/// A keyboard-safe multiline prompt field with one send-or-stop action.
final class AssistantComposer extends StatelessWidget {
  /// Creates a composer controlled by the owning assistant page.
  const AssistantComposer({
    required this.controller,
    required this.generating,
    required this.canSubmit,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  /// Owns the editable prompt text outside Bloc state.
  final TextEditingController controller;

  /// Whether the action control currently cancels generation.
  final bool generating;

  /// Whether a non-empty prompt may start generation.
  final bool canSubmit;

  /// Starts generation with the current controller value.
  final VoidCallback onSend;

  /// Cooperatively cancels active generation.
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const radius = AppRadius.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final actionLabel = generating ? localizations.assistantStopAction : localizations.assistantSendAction;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.muted.withValues(alpha: 0.18)),
        ),
      ),
      child: Padding(
        padding: spacing.section,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                label: localizations.assistantPromptLabel,
                textField: true,
                child: CupertinoTextField(
                  key: assistantPromptFieldKey,
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: AssistantBloc.manualPromptCharacterLimit,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  padding: spacing.section,
                  placeholder: localizations.assistantPromptPlaceholder,
                  style: typography.body.copyWith(color: colors.onSurface),
                  placeholderStyle: typography.body.copyWith(
                    color: colors.muted,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border.all(
                      color: colors.muted.withValues(alpha: 0.25),
                    ),
                    borderRadius: radius.lg,
                  ),
                ),
              ),
            ),
            Padding(
              padding: spacing.startSm,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  final sendEnabled = canSubmit && value.text.trim().isNotEmpty;
                  return Semantics(
                    button: true,
                    label: actionLabel,
                    child: CupertinoButton.filled(
                      key: assistantSubmitControlKey,
                      padding: spacing.compactControl,
                      onPressed: generating
                          ? onStop
                          : sendEnabled
                          ? onSend
                          : null,
                      child: Text(actionLabel),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
