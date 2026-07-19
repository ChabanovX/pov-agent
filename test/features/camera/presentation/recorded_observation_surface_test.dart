import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/recorded_observation_frame.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/debug/recorded_bus_fixture.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/presentation/widgets/recorded_observation_surface.dart';

void main() {
  testWidgets('renders an empty surface before the decoder publishes a frame', (
    tester,
  ) async {
    final source = _EmptyRecordedObservationFrameSource();
    try {
      await tester.pumpWidget(
        CupertinoApp(
          home: RecordedObservationSurface(frameSource: source),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RecordedObservationSurface),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    } finally {
      await source.close();
    }
  });

  testWidgets('renders a recorded detection with matching semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final source = _FakeRecordedObservationFrameSource();
    try {
      await tester.pumpWidget(
        CupertinoApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: RecordedObservationSurface(frameSource: source),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RecordedObservationSurface),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(find.semantics.byLabel('person 90%'), findsOne);
      expect(
        tester.getSize(find.byType(Image)).aspectRatio,
        closeTo(
          source.currentFrame.aspectRatio,
          0.001,
        ),
      );
    } finally {
      semantics.dispose();
      await source.close();
    }
  });
}

final class _EmptyRecordedObservationFrameSource implements RecordedObservationFrameSource {
  final StreamController<RecordedObservationFrame> _frames = StreamController<RecordedObservationFrame>.broadcast();

  @override
  RecordedObservationFrame? get currentFrame => null;

  @override
  Stream<RecordedObservationFrame> get frames => _frames.stream;

  Future<void> close() => _frames.close();
}

final class _FakeRecordedObservationFrameSource implements RecordedObservationFrameSource {
  _FakeRecordedObservationFrameSource() : this._(recordedBusFixture(frameCount: 1));

  _FakeRecordedObservationFrameSource._(RecordedObservationFixture fixture)
    : currentFrame = RecordedObservationFrame(
        encodedImage: fixture.frames.single,
        detections: const [
          Detection(
            classId: 0,
            label: 'person',
            confidence: 0.9,
            box: NormalizedBox(
              left: 0.1,
              top: 0.2,
              right: 0.6,
              bottom: 0.9,
            ),
          ),
        ],
        frameNumber: 1,
        frameWidth: fixture.frameWidth,
        frameHeight: fixture.frameHeight,
      );

  final StreamController<RecordedObservationFrame> _frames = StreamController<RecordedObservationFrame>.broadcast();

  @override
  final RecordedObservationFrame currentFrame;

  @override
  Stream<RecordedObservationFrame> get frames => _frames.stream;

  Future<void> close() => _frames.close();
}
