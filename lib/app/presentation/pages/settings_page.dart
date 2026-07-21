import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';

const double _modelStatusIconSize = 17;
const double _privacyIconSize = 15;
const double _privacyIconGap = 9;

/// The native iOS Settings destination for session preferences and local
/// runtime transparency.
final class SettingsPage extends StatelessWidget {
  /// Creates Settings from the verified model-pack projection.
  const SettingsPage({
    required this.modelPackState,
    super.key,
  });

  /// The app-root model state shown as read-only verification rows.
  final ModelPackState modelPackState;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.dark.background,
      child: SafeArea(
        bottom: false,
        child: BlocBuilder<ObserverBloc, ObserverState>(
          builder: (context, observerState) {
            return BlocBuilder<CameraBloc, CameraState>(
              builder: (context, cameraState) {
                return CustomScrollView(
                  key: const ValueKey('settings-scroll-view'),
                  slivers: [
                    CupertinoSliverNavigationBar(
                      backgroundColor: AppColors.dark.background,
                      border: null,
                      largeTitle: Text(
                        AppLocalizations.of(context).settingsTitle,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SettingsContent(
                        observerState: observerState,
                        cameraState: cameraState,
                        modelPackState: modelPackState,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

final class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.observerState,
    required this.cameraState,
    required this.modelPackState,
  });

  final ObserverState observerState;
  final CameraState cameraState;
  final ModelPackState modelPackState;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoListSection.insetGrouped(
          header: Text(localizations.settingsObservationSection),
          footer: Text(localizations.settingsObservationFooter),
          backgroundColor: AppColors.dark.background,
          decoration: _sectionDecoration,
          children: [
            _DisclosureTile(
              title: localizations.settingsCommentInterval,
              value: _intervalLabel(localizations, observerState.interval),
              onTap: () => _showIntervalPicker(
                context,
                selected: observerState.interval,
              ),
            ),
            _ValueTile(
              title: localizations.settingsObservationStatus,
              value: localizations.settingsPausedStatus,
              valueColor: AppColors.dark.textSecondary,
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: Text(localizations.settingsAudioVoiceSection),
          backgroundColor: AppColors.dark.background,
          decoration: _sectionDecoration,
          children: [
            _SwitchTile(
              title: localizations.settingsSpeakResponses,
              value: !observerState.speechMuted,
              onChanged: (enabled) {
                context.read<ObserverBloc>().add(
                  ObserverSpeechMutedChanged(muted: !enabled),
                );
              },
            ),
            _SwitchTile(
              title: localizations.settingsHandsFreeListening,
              value: observerState.handsFreeEnabled,
              onChanged: (enabled) {
                if (enabled) {
                  _showMicrophoneRationale(context);
                } else {
                  context.read<ObserverBloc>().add(
                    const ObserverHandsFreeEnabledChanged(enabled: false),
                  );
                }
              },
            ),
            _ValueTile(
              title: localizations.settingsWakePhrase,
              value: localizations.settingsWakePhraseValue(
                observerState.wakePhrase,
              ),
            ),
            if (observerState.canOpenMicrophoneSettings)
              _DisclosureTile(
                title: localizations.settingsMicrophoneAccess,
                value: localizations.settingsPermissionDenied,
                valueColor: AppColors.dark.danger,
                onTap: () {
                  context.read<ObserverBloc>().add(
                    const ObserverMicrophoneSettingsRequested(),
                  );
                },
              ),
            if (observerState.hasMicrophonePermissionFailure && !observerState.canOpenMicrophoneSettings)
              _ValueTile(
                title: localizations.settingsMicrophoneAccess,
                value: localizations.settingsPermissionRestricted,
                valueColor: AppColors.dark.danger,
              ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: Text(localizations.settingsModelsSection),
          backgroundColor: AppColors.dark.background,
          decoration: _sectionDecoration,
          children: [
            for (final item in modelPackState.items) _ModelTile(item: item),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: Text(localizations.settingsPrivacySection),
          backgroundColor: AppColors.dark.background,
          decoration: _sectionDecoration,
          children: [
            _DisclosureTile(
              title: localizations.settingsPrivacySummary,
              onTap: () => _showPrivacyDetails(context),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: Text(localizations.settingsDiagnosticsSection),
          backgroundColor: AppColors.dark.background,
          decoration: _sectionDecoration,
          children: [
            _DisclosureTile(
              title: localizations.settingsDiagnosticsAndLicenses,
              onTap: () => _showDiagnostics(context, cameraState),
            ),
          ],
        ),
        Padding(padding: AppSpacing.regular.topLg),
      ],
    );
  }
}

BoxDecoration get _sectionDecoration {
  return BoxDecoration(
    color: AppColors.dark.surface,
    borderRadius: AppRadius.regular.compact,
    border: Border.all(
      color: AppColors.dark.border,
      width: AppSizes.regular.hairlineWidth,
    ),
  );
}

final class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.title,
    required this.value,
    this.valueColor,
  });

  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Row(
        children: [
          Text(title),
          Expanded(
            child: Padding(
              padding: AppSpacing.regular.startMd,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.regular.metadata.copyWith(
                  color: valueColor ?? AppColors.dark.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DisclosureTile extends StatelessWidget {
  const _DisclosureTile({
    required this.title,
    required this.onTap,
    this.value,
    this.valueColor,
  });

  final String title;
  final String? value;
  final Color? valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(title),
      additionalInfo: value == null
          ? null
          : Text(
              value!,
              style: AppTypography.regular.metadata.copyWith(
                color: valueColor ?? AppColors.dark.textSecondary,
              ),
            ),
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: AppSpacing.regular.md,
        color: AppColors.dark.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

final class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: title,
      toggled: value,
      onTap: () => onChanged(!value),
      child: ExcludeSemantics(
        child: CupertinoListTile(
          title: Text(title),
          trailing: CupertinoSwitch(
            value: value,
            activeTrackColor: AppColors.dark.success,
            onChanged: onChanged,
          ),
          onTap: () => onChanged(!value),
        ),
      ),
    );
  }
}

final class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.item});

  final ModelPackItemState item;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final verified = item.phase == ModelPackItemPhase.verified;
    final title = _modelTitle(localizations, item.kind);
    final status = verified ? localizations.settingsModelVerified : localizations.settingsModelNeedsAttention;
    return Semantics(
      container: true,
      label: localizations.modelSetupModelAccessibilityLabel(
        title,
        item.technicalName,
        status,
      ),
      excludeSemantics: true,
      child: CupertinoListTile(
        title: Text(title),
        subtitle: Text(
          item.technicalName,
          style: AppTypography.regular.metadata.copyWith(
            color: AppColors.dark.textSecondary,
          ),
        ),
        additionalInfo: Text(
          status,
          style: AppTypography.regular.metadata.copyWith(
            color: verified ? AppColors.dark.success : AppColors.dark.warning,
          ),
        ),
        trailing: Icon(
          verified ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.exclamationmark_triangle_fill,
          size: _modelStatusIconSize,
          color: verified ? AppColors.dark.success : AppColors.dark.warning,
        ),
      ),
    );
  }
}

void _showIntervalPicker(
  BuildContext context, {
  required ObserverInterval selected,
}) {
  final observerBloc = context.read<ObserverBloc>();
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        final localizations = AppLocalizations.of(sheetContext);
        return _SettingsSheet(
          title: localizations.settingsCommentInterval,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final interval in ObserverInterval.values)
                CupertinoListTile(
                  title: Text(_intervalLabel(localizations, interval)),
                  trailing: interval == selected
                      ? Icon(
                          CupertinoIcons.checkmark,
                          color: AppColors.dark.success,
                        )
                      : null,
                  onTap: () {
                    observerBloc.add(ObservationIntervalSelected(interval));
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

void _showMicrophoneRationale(BuildContext context) {
  final observerBloc = context.read<ObserverBloc>();
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        final localizations = AppLocalizations.of(sheetContext);
        return _SettingsSheet(
          title: localizations.microphoneRationaleTitle,
          child: Padding(
            padding: AppSpacing.regular.microphoneSheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.mic_fill,
                  size: AppSizes.regular.sheetIcon,
                  color: AppColors.dark.listening,
                ),
                Padding(
                  padding: AppSpacing.regular.topOverlay,
                  child: Text(
                    localizations.microphoneRationaleMessage,
                    textAlign: TextAlign.center,
                    style: AppTypography.regular.body.copyWith(
                      color: AppColors.dark.textSecondary,
                    ),
                  ),
                ),
                Padding(
                  padding: AppSpacing.regular.topMd,
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(
                      width: double.infinity,
                      height: AppSizes.regular.primaryActionHeight,
                    ),
                    child: CupertinoButton(
                      color: AppColors.dark.actionPrimary,
                      borderRadius: AppRadius.regular.action,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        observerBloc.add(
                          const ObserverHandsFreeEnabledChanged(enabled: true),
                        );
                      },
                      child: Text(
                        localizations.enableMicrophoneAction,
                        style: AppTypography.regular.label.copyWith(
                          color: AppColors.dark.onActionPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _showPrivacyDetails(BuildContext context) {
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        final localizations = AppLocalizations.of(sheetContext);
        return _SettingsSheet(
          title: localizations.settingsPrivacySection,
          child: Padding(
            padding: AppSpacing.regular.privacySheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final statement in [
                  localizations.privacyProcessingStatement,
                  localizations.privacyMediaStatement,
                  localizations.privacyConversationStatement,
                  localizations.privacyQwenStatement,
                  localizations.privacyLifecycleStatement,
                ])
                  Padding(
                    padding: AppSpacing.regular.bottomComponent,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.lock_fill,
                          size: _privacyIconSize,
                          color: AppColors.dark.success,
                        ),
                        Expanded(
                          child: Padding(
                            padding: AppSpacing.regular.startSm.copyWith(
                              start: _privacyIconGap,
                            ),
                            child: Text(
                              statement,
                              style: AppTypography.regular.body.copyWith(
                                color: AppColors.dark.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _showDiagnostics(BuildContext context, CameraState state) {
  unawaited(
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        final localizations = AppLocalizations.of(sheetContext);
        final diagnostics = state.diagnostics;
        return _SettingsSheet(
          title: localizations.settingsDiagnosticsAndLicenses,
          child: Padding(
            padding: AppSpacing.regular.privacySheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DiagnosticRow(
                  label: localizations.settingsCurrentPerformance,
                  value: diagnostics == null
                      ? localizations.assistantDiagnosticsPending
                      : localizations.assistantDiagnosticsLabel(
                          diagnostics.framesPerSecond.round(),
                          diagnostics.inferenceTimeMs.round(),
                        ),
                ),
                _DiagnosticRow(
                  label: localizations.settingsThermalState,
                  value: localizations.settingsThermalNominal,
                ),
                _DiagnosticRow(
                  label: localizations.settingsRuntimeVersions,
                  value: localizations.settingsRuntimeVersionsValue,
                ),
                _DiagnosticRow(
                  label: localizations.settingsLicenses,
                  value: localizations.settingsLicensesValue,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

final class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dark.surface,
            borderRadius: AppRadius.regular.sheet,
            border: Border(top: BorderSide(color: AppColors.dark.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSizes.regular.sheetGrabberWidth,
                height: AppSizes.regular.sheetGrabberHeight,
                margin: AppSpacing.regular.topSm,
                decoration: BoxDecoration(
                  color: AppColors.dark.border,
                  borderRadius: AppRadius.regular.full,
                ),
              ),
              Padding(
                padding: AppSpacing.regular.settingsSheetHeader,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.regular.title.copyWith(
                          color: AppColors.dark.textPrimary,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      minimumSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: AppColors.dark.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.regular.diagnosticRow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.regular.body.copyWith(
                color: AppColors.dark.textPrimary,
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: AppSpacing.regular.startMd,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.regular.metadata.copyWith(
                  color: AppColors.dark.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _modelTitle(
  AppLocalizations localizations,
  ModelPackItemKind kind,
) {
  return switch (kind) {
    ModelPackItemKind.assistant => localizations.modelSetupAssistantModelLabel,
    ModelPackItemKind.vision => localizations.modelSetupVisionModelLabel,
    ModelPackItemKind.voice => localizations.modelSetupVoiceModelLabel,
    ModelPackItemKind.listening => localizations.modelSetupListeningModelLabel,
  };
}

String _intervalLabel(
  AppLocalizations localizations,
  ObserverInterval interval,
) {
  return switch (interval) {
    ObserverInterval.tenSeconds => localizations.settingsIntervalTenSeconds,
    ObserverInterval.thirtySeconds => localizations.settingsIntervalThirtySeconds,
    ObserverInterval.oneMinute => localizations.settingsIntervalOneMinute,
    ObserverInterval.twoMinutes => localizations.settingsIntervalTwoMinutes,
    ObserverInterval.fiveMinutes => localizations.settingsIntervalFiveMinutes,
  };
}
