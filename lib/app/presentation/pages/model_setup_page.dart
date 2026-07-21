import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/core/constants/app_assets.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// The mandatory iOS root screen for preparing every on-device model.
///
/// This page is a pure projection of [state]. App composition owns the model
/// controller and replaces this gate only after [ModelPackPhase.complete].
final class ModelSetupPage extends StatelessWidget {
  /// Creates the required-model setup gate.
  const ModelSetupPage({
    required this.state,
    required this.onPrimaryAction,
    required this.onCancel,
    required this.onRetry,
    required this.onCheckAgain,
    super.key,
  });

  /// The complete model-pack state rendered by this page.
  final ModelPackState state;

  /// Starts installation after device preflight succeeds.
  final VoidCallback onPrimaryAction;

  /// Stops unverified transfers while retaining verified model artifacts.
  final VoidCallback onCancel;

  /// Retries a failed transfer or verification attempt.
  final VoidCallback onRetry;

  /// Rechecks free storage after the user has made space.
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const spacing = AppSpacing.regular;
    const sizes = AppSizes.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return CupertinoScrollbar(
              child: SingleChildScrollView(
                primary: true,
                padding: spacing.horizontalMd,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sizes.maxContentWidth,
                      minHeight: viewport.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SpacingGap(padding: spacing.topMd),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Semantics(
                              image: true,
                              label: localizations.appTitle,
                              excludeSemantics: true,
                              child: Image(
                                image: AppAssets.povAgentMark,
                                width: sizes.heroIcon,
                                height: sizes.heroIcon,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          _SpacingGap(padding: spacing.topMd),
                          Semantics(
                            header: true,
                            child: Text(
                              localizations.modelSetupTitle,
                              style: typography.hero.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          _SpacingGap(padding: spacing.topSm),
                          Text(
                            localizations.modelSetupDescription,
                            style: typography.label.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          _SpacingGap(padding: spacing.topComponent),
                          const _PrivacyStatement(),
                          _SpacingGap(padding: spacing.topLg),
                          _ModelList(items: state.items),
                          _SpacingGap(padding: spacing.topMd),
                          _DownloadSummary(state: state),
                          if (_showsOverallProgress(state)) ...[
                            _SpacingGap(padding: spacing.topComponent),
                            _OverallProgress(progress: state.overallProgress),
                          ],
                          if (state.phase == ModelPackPhase.failure) ...[
                            _SpacingGap(padding: spacing.topComponent),
                            _FailureBanner(state: state),
                          ],
                          const Spacer(),
                          _SpacingGap(padding: spacing.topLg),
                          _SetupAction(
                            state: state,
                            onPrimary: onPrimaryAction,
                            onCancel: onCancel,
                            onRetry: onRetry,
                            onCheckAgain: onCheckAgain,
                          ),
                          _SpacingGap(padding: spacing.topComponent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _PrivacyStatement extends StatelessWidget {
  const _PrivacyStatement();

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.lock,
            color: colors.muted,
            size: spacing.md,
          ),
          Expanded(
            child: Padding(
              padding: spacing.startSm,
              child: Text(
                localizations.modelSetupPrivacyMessage,
                style: typography.status.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ModelList extends StatelessWidget {
  const _ModelList({required this.items});

  final List<ModelPackItemState> items;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.regular;

    return Column(
      children: [
        for (var index = 0; index < items.length; index += 1) ...[
          _ModelRow(item: items[index]),
          if (index != items.length - 1) _SpacingGap(padding: spacing.topSm),
        ],
      ],
    );
  }
}

final class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.item});

  final ModelPackItemState item;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final title = _itemTitle(localizations, item.kind);
    final status = _itemStatus(localizations, item);
    final statusColor = _itemStatusColor(item.phase);

    return Semantics(
      key: ValueKey('model-setup-${item.kind.name}-row'),
      container: true,
      label: localizations.modelSetupModelAccessibilityLabel(
        title,
        item.technicalName,
        status,
      ),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.kind == ModelPackItemKind.assistant ? colors.surfaceRaised : colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: radius.sm,
        ),
        child: Padding(
          padding: spacing.section,
          child: Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: spacing.xl),
                child: Icon(
                  _itemIcon(item.kind),
                  color: _itemIconColor(item.kind),
                  size: sizes.icon,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: spacing.startSm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.label.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: item.technicalName,
                              style: typography.metadata.copyWith(
                                color: colors.muted,
                              ),
                            ),
                            TextSpan(
                              text: '  ·  ',
                              style: typography.metadata.copyWith(
                                color: colors.muted,
                              ),
                            ),
                            TextSpan(
                              text: status,
                              style: typography.metadata.copyWith(
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.metadata,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: spacing.startSm,
                child: _ModelStatusGlyph(item: item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ModelStatusGlyph extends StatelessWidget {
  const _ModelStatusGlyph({required this.item});

  final ModelPackItemState item;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const sizes = AppSizes.regular;

    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(
        width: sizes.statusBadgeHeight,
        height: sizes.statusBadgeHeight,
      ),
      child: Center(
        child: switch (item.phase) {
          ModelPackItemPhase.preparing => const CupertinoActivityIndicator(),
          ModelPackItemPhase.downloading => _CircularProgressGlyph(
            progress: item.progress ?? 0,
            color: colors.listening,
          ),
          ModelPackItemPhase.verifying => CupertinoActivityIndicator(
            color: colors.onSurface,
          ),
          ModelPackItemPhase.verified => Icon(
            CupertinoIcons.check_mark_circled,
            color: colors.success,
            size: sizes.icon,
          ),
          ModelPackItemPhase.failure => Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: colors.danger,
            size: sizes.icon,
          ),
          ModelPackItemPhase.waiting => Icon(
            CupertinoIcons.arrow_down_circle,
            color: colors.muted,
            size: sizes.icon,
          ),
        },
      ),
    );
  }
}

final class _DownloadSummary extends StatelessWidget {
  const _DownloadSummary({required this.state});

  final ModelPackState state;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);

    return Text(
      localizations.modelSetupDownloadSummary(
        _formatBytes(state.totalDownloadBytes),
        _formatBytes(ModelPackState.requiredStorageBytes),
      ),
      style: typography.metadata.copyWith(color: colors.textSecondary),
      textAlign: TextAlign.center,
    );
  }
}

final class _OverallProgress extends StatelessWidget {
  const _OverallProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final normalized = progress.clamp(0, 1).toDouble();
    final percent = (normalized * 100).round();

    return Semantics(
      container: true,
      label: localizations.modelSetupOverallProgressLabel,
      value: localizations.modelSetupPercentValue(percent),
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                localizations.modelSetupOverallProgressLabel,
                style: typography.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Text(
                localizations.modelSetupPercentValue(percent),
                style: typography.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          _SpacingGap(padding: spacing.topSm),
          ClipRRect(
            borderRadius: radius.full,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(height: spacing.sm),
              child: ColoredBox(
                color: colors.surfaceRaised,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: normalized,
                    child: ColoredBox(color: colors.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.state});

  final ModelPackState state;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final localizations = AppLocalizations.of(context);
    final failure = _modelPackFailure(state);
    final message = _failureMessage(localizations, state, failure);
    final critical = _isIntegrityFailure(failure);
    final accent = critical ? colors.danger : colors.warning;

    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
          borderRadius: radius.sm,
        ),
        child: Padding(
          padding: spacing.insetComponent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: accent,
                size: sizes.icon,
              ),
              Expanded(
                child: Padding(
                  padding: spacing.startSm,
                  child: Text(
                    message,
                    style: typography.metadata.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SetupAction extends StatelessWidget {
  const _SetupAction({
    required this.state,
    required this.onPrimary,
    required this.onCancel,
    required this.onRetry,
    required this.onCheckAgain,
  });

  final ModelPackState state;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final activeItem = state.activeItem;

    return switch (state.phase) {
      ModelPackPhase.checking => _ActionButton(
        label: localizations.modelSetupCheckingAction,
      ),
      ModelPackPhase.ready => _ActionButton(
        label: localizations.modelSetupDownloadAction,
        onPressed: onPrimary,
      ),
      ModelPackPhase.installing when activeItem?.phase == ModelPackItemPhase.verifying => _ActionButton(
        label: localizations.modelSetupVerifyingAction,
      ),
      ModelPackPhase.installing => _ActionButton(
        label: localizations.modelSetupCancelAction,
        onPressed: onCancel,
        outlined: true,
      ),
      ModelPackPhase.cancelling => _ActionButton(
        label: localizations.modelSetupCancellingAction,
        outlined: true,
      ),
      ModelPackPhase.complete => _ActionButton(
        label: localizations.modelSetupCompleteAction,
      ),
      ModelPackPhase.failure => _failureAction(
        localizations,
        state,
        onRetry: onRetry,
        onCheckAgain: onCheckAgain,
      ),
    };
  }
}

final class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    const radius = AppRadius.regular;
    const sizes = AppSizes.regular;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: outlined ? Border.all(color: colors.border) : null,
        borderRadius: radius.sm,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(
          height: sizes.primaryActionHeight,
        ),
        child: CupertinoButton(
          borderRadius: radius.sm,
          color: outlined ? colors.background.withValues(alpha: 0) : colors.actionPrimary,
          disabledColor: outlined ? colors.background.withValues(alpha: 0) : colors.surfaceRaised,
          onPressed: onPressed,
          padding: spacing.insetSm,
          child: Text(
            label,
            style: typography.label.copyWith(
              color: !enabled
                  ? colors.textSecondary
                  : outlined
                  ? colors.textPrimary
                  : colors.onActionPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

final class _CircularProgressGlyph extends StatelessWidget {
  const _CircularProgressGlyph({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const sizes = AppSizes.regular;

    return CustomPaint(
      size: Size.square(sizes.icon),
      painter: _CircularProgressPainter(
        progress: progress.clamp(0, 1).toDouble(),
        color: color,
      ),
    );
  }
}

final class _SpacingGap extends StatelessWidget {
  const _SpacingGap({required this.padding});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: const SizedBox.shrink(),
    );
  }
}

final class _CircularProgressPainter extends CustomPainter {
  const _CircularProgressPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 2) / 2;
    final track = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final value = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    canvas
      ..drawCircle(center, radius, track)
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        value,
      );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return progress != oldDelegate.progress || color != oldDelegate.color;
  }
}

Widget _failureAction(
  AppLocalizations localizations,
  ModelPackState state, {
  required VoidCallback onRetry,
  required VoidCallback onCheckAgain,
}) {
  final failure = _modelPackFailure(state);
  if (_isStorageFailure(failure)) {
    return _ActionButton(
      label: localizations.modelSetupCheckAgainAction,
      onPressed: onCheckAgain,
    );
  }
  if (_isIntegrityFailure(failure)) {
    return _ActionButton(
      label: localizations.modelSetupDownloadAgainAction,
      onPressed: onRetry,
    );
  }
  if (failure is NetworkFailure) {
    return _ActionButton(
      label: localizations.modelSetupTryAgainAction,
      onPressed: onRetry,
    );
  }
  return _ActionButton(
    label: localizations.modelSetupRetryAction,
    onPressed: onRetry,
  );
}

String _failureMessage(
  AppLocalizations localizations,
  ModelPackState state,
  AppFailure? failure,
) {
  if (_isStorageFailure(failure)) {
    final availableStorageBytes = state.availableStorageBytes;
    if (availableStorageBytes == null) {
      return localizations.modelSetupFailureMessage;
    }
    return localizations.modelSetupStorageMessage(
      _formatBytes(ModelPackState.requiredStorageBytes),
      _formatBytes(availableStorageBytes),
    );
  }
  if (_isIntegrityFailure(failure)) {
    return localizations.modelSetupIntegrityMessage;
  }
  if (failure is NetworkFailure) {
    return localizations.modelSetupOfflineMessage;
  }
  return localizations.modelSetupFailureMessage;
}

AppFailure? _modelPackFailure(ModelPackState state) {
  final rootFailure = state.failure;
  if (rootFailure != null) return rootFailure;
  for (final item in state.items) {
    final itemFailure = item.failure;
    if (itemFailure != null) return itemFailure;
  }
  return null;
}

bool _isStorageFailure(AppFailure? failure) {
  return failure?.code == 'model_pack_insufficient_storage';
}

bool _isIntegrityFailure(AppFailure? failure) {
  final code = failure?.code ?? '';
  return code.contains('integrity') || code.contains('checksum');
}

bool _showsOverallProgress(ModelPackState state) {
  return state.phase == ModelPackPhase.installing ||
      state.phase == ModelPackPhase.cancelling ||
      state.phase == ModelPackPhase.complete;
}

String _itemStatus(
  AppLocalizations localizations,
  ModelPackItemState item,
) {
  return switch (item.phase) {
    ModelPackItemPhase.waiting => localizations.modelSetupModelWaitingStatus,
    ModelPackItemPhase.preparing => localizations.modelSetupModelPreparingStatus,
    ModelPackItemPhase.downloading => localizations.modelSetupModelDownloadingStatus(
      ((item.progress ?? 0) * 100).round(),
    ),
    ModelPackItemPhase.verifying => localizations.modelSetupModelVerifyingStatus,
    ModelPackItemPhase.verified => localizations.modelSetupModelVerifiedStatus,
    ModelPackItemPhase.failure => localizations.modelSetupModelFailureStatus,
  };
}

String _itemTitle(
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

Color _itemStatusColor(ModelPackItemPhase phase) {
  const colors = AppColors.dark;
  return switch (phase) {
    ModelPackItemPhase.downloading => colors.listening,
    ModelPackItemPhase.verified => colors.success,
    ModelPackItemPhase.failure => colors.danger,
    ModelPackItemPhase.preparing || ModelPackItemPhase.verifying => colors.textPrimary,
    ModelPackItemPhase.waiting => colors.textSecondary,
  };
}

IconData _itemIcon(ModelPackItemKind kind) {
  return switch (kind) {
    ModelPackItemKind.assistant => CupertinoIcons.sparkles,
    ModelPackItemKind.vision => CupertinoIcons.eye_fill,
    ModelPackItemKind.voice => CupertinoIcons.waveform,
    ModelPackItemKind.listening => CupertinoIcons.ear,
  };
}

Color _itemIconColor(ModelPackItemKind kind) {
  const colors = AppColors.dark;
  return switch (kind) {
    ModelPackItemKind.assistant => colors.success,
    ModelPackItemKind.vision => colors.listening,
    ModelPackItemKind.voice || ModelPackItemKind.listening => colors.textPrimary,
  };
}

String _formatBytes(int bytes) {
  const kibibyte = 1024;
  const mebibyte = kibibyte * 1024;
  const gibibyte = mebibyte * 1024;
  if (bytes >= gibibyte) {
    return '${_compactDecimal(bytes / gibibyte)} GB';
  }
  if (bytes >= mebibyte) {
    return '${_compactDecimal(bytes / mebibyte)} MB';
  }
  if (bytes >= kibibyte) {
    return '${_compactDecimal(bytes / kibibyte)} KB';
  }
  return '$bytes B';
}

String _compactDecimal(double value) {
  final rounded = value.roundToDouble();
  return value == rounded ? rounded.toInt().toString() : value.toStringAsFixed(1);
}
