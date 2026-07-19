import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/features/camera/application/models/recorded_observation_frame.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';

/// A surface for recorded frames with Flutter-rendered YOLO detections.
final class RecordedObservationSurface extends StatelessWidget {
  /// Creates a surface that renders frames from [frameSource].
  const RecordedObservationSurface({
    required this.frameSource,
    super.key,
  });

  /// The source of synchronized recorded frames and detections.
  final RecordedObservationFrameSource frameSource;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.light;
    const spacing = AppSpacing.regular;
    const typography = AppTypography.regular;

    return ColoredBox(
      color: colors.onSurface,
      child: StreamBuilder<RecordedObservationFrame>(
        initialData: frameSource.currentFrame,
        stream: frameSource.frames,
        builder: (context, snapshot) {
          final frame = snapshot.data;
          if (frame == null) return const SizedBox.expand();
          return Center(
            child: AspectRatio(
              aspectRatio: frame.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    frame.encodedImage,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  CustomPaint(
                    painter: _RecordedDetectionPainter(
                      frame,
                      boxColor: colors.primary,
                      boxStrokeWidth: spacing.xs / 2,
                      labelBackgroundColor: colors.onSurface,
                      labelInset: spacing.xs,
                      labelTextStyle: typography.label.copyWith(
                        color: colors.onPrimary,
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
}

final class _RecordedDetectionPainter extends CustomPainter {
  const _RecordedDetectionPainter(
    this.frame, {
    required this.boxColor,
    required this.boxStrokeWidth,
    required this.labelBackgroundColor,
    required this.labelInset,
    required this.labelTextStyle,
  });

  final RecordedObservationFrame frame;
  final Color boxColor;
  final double boxStrokeWidth;
  final Color labelBackgroundColor;
  final double labelInset;
  final TextStyle labelTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = boxStrokeWidth;
    final labelBackgroundPaint = Paint()
      ..color = labelBackgroundColor
      ..style = PaintingStyle.fill;

    for (final detection in frame.detections) {
      final rect = _detectionRect(detection, size);
      canvas.drawRect(rect, boxPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: _detectionDescription(detection),
          style: labelTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final labelWidth = textPainter.width + (labelInset * 2);
      final labelHeight = textPainter.height + labelInset;
      final maxLabelLeft = (size.width - labelWidth).clamp(0, size.width).toDouble();
      final maxLabelTop = (size.height - labelHeight).clamp(0, size.height).toDouble();
      final labelRect = Rect.fromLTWH(
        rect.left.clamp(0, maxLabelLeft).toDouble(),
        (rect.top - labelHeight).clamp(0, maxLabelTop).toDouble(),
        labelWidth,
        labelHeight,
      );
      canvas.drawRect(labelRect, labelBackgroundPaint);
      textPainter.paint(
        canvas,
        Offset(
          labelRect.left + labelInset,
          labelRect.top + (labelInset / 2),
        ),
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder {
    return (size) {
      return frame.detections
          .map((detection) {
            return CustomPainterSemantics(
              rect: _detectionRect(detection, size),
              properties: SemanticsProperties(
                label: _detectionDescription(detection),
                textDirection: TextDirection.ltr,
              ),
            );
          })
          .toList(growable: false);
    };
  }

  @override
  bool shouldRepaint(_RecordedDetectionPainter oldDelegate) {
    return oldDelegate.frame.frameNumber != frame.frameNumber || oldDelegate.frame.detections != frame.detections;
  }

  @override
  bool shouldRebuildSemantics(_RecordedDetectionPainter oldDelegate) {
    return shouldRepaint(oldDelegate);
  }
}

Rect _detectionRect(Detection detection, Size size) {
  final box = detection.box;
  return Rect.fromLTRB(
    box.left * size.width,
    box.top * size.height,
    box.right * size.width,
    box.bottom * size.height,
  );
}

String _detectionDescription(Detection detection) {
  return '${detection.label} ${(detection.confidence * 100).round()}%';
}
