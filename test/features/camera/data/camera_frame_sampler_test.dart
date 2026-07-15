import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/camera_frame_sampler.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';

void main() {
  test('samples immediately and then no more than once per second', () {
    var elapsed = Duration.zero;
    var copies = 0;
    final sampler = CameraFrameSampler(elapsedTime: () => elapsed);

    CameraFrameDto createFrame() {
      copies += 1;
      return _frame();
    }

    expect(sampler.sample(createFrame), isNotNull);

    elapsed = const Duration(milliseconds: 999);
    expect(sampler.sample(createFrame), isNull);
    expect(copies, 1, reason: 'Dropped native frames must not copy pixel bytes.');

    elapsed = const Duration(seconds: 1);
    expect(sampler.sample(createFrame), isNotNull);
    expect(copies, 2);
  });

  test('reset allows the next frame through immediately', () {
    var elapsed = Duration.zero;
    final sampler = CameraFrameSampler(elapsedTime: () => elapsed);

    expect(sampler.sample(_frame), isNotNull);
    elapsed = const Duration(milliseconds: 100);
    expect(sampler.sample(_frame), isNull);

    sampler.reset();

    expect(sampler.sample(_frame), isNotNull);
  });
}

CameraFrameDto _frame() {
  return CameraFrameDto(
    width: 2,
    height: 2,
    format: CameraFrameFormatDto.yuv420,
    planes: [
      CameraFramePlaneDto(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        bytesPerRow: 2,
        bytesPerPixel: 1,
        width: 2,
        height: 2,
      ),
    ],
    lens: CameraLensDto.back,
    sensorOrientationDegrees: 90,
    capturedAt: DateTime.utc(2026),
  );
}
