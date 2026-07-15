import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as plugin;
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/camera_driver.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/camera_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/camera_controller_impl.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_frame.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

void main() {
  late _FakeCameraDriver driver;
  late CameraControllerImpl controller;

  setUp(() {
    driver = _FakeCameraDriver();
    controller = CameraControllerImpl(driver, const CameraFailureMapper());
  });

  tearDown(() async {
    await driver.close();
  });

  test('discovers supported lenses, prefers rear, and enables by lens', () async {
    driver.devices = const [
      CameraDeviceDto(
        id: 'external',
        lens: CameraLensDto.external,
        sensorOrientationDegrees: 0,
      ),
      CameraDeviceDto(
        id: 'front',
        lens: CameraLensDto.front,
        sensorOrientationDegrees: 270,
      ),
      CameraDeviceDto(
        id: 'rear',
        lens: CameraLensDto.back,
        sensorOrientationDegrees: 90,
      ),
    ];

    final initResult = await controller.init();
    final capabilities = (initResult as AppSuccess<CameraCapabilities>).value;

    expect(capabilities.availableLenses, [CameraLens.front, CameraLens.back]);
    expect(capabilities.preferredLens, CameraLens.back);

    expect(await controller.enable(CameraLens.back), isA<AppSuccess<void>>());
    expect(driver.enabledDevices.single.id, 'rear');
  });

  test('maps and owns raw frame bytes at the repository boundary', () async {
    await controller.init();
    final dto = _frameDto();
    final resultFuture = controller.frames.first;

    driver.addFrame(dto);
    final result = await resultFuture;
    final frame = (result as AppSuccess<CameraFrame>).value;
    dto.planes.single.bytes[0] = 99;

    expect(frame.format, CameraFrameFormat.bgra8888);
    expect(frame.lens, CameraLens.front);
    expect(frame.planes.single.bytes, [1, 2, 3, 4]);
    expect(frame.capturedAt.isUtc, isTrue);
  });

  test('normalizes the camera plugin permission error', () async {
    driver.listError = plugin.CameraException(
      'CameraAccessDeniedWithoutPrompt',
      'Permission was denied earlier.',
    );

    final result = await controller.init();

    expect(result, isA<AppError<CameraCapabilities>>());
    expect(
      (result as AppError<CameraCapabilities>).failure,
      isA<PermissionDeniedFailure>(),
    );
  });

  test('reports no supported camera as device unavailable', () async {
    driver.devices = const [];

    final result = await controller.init();

    expect((result as AppError).failure, isA<DeviceUnavailableFailure>());
  });
}

CameraFrameDto _frameDto() {
  return CameraFrameDto(
    width: 2,
    height: 2,
    format: CameraFrameFormatDto.bgra8888,
    planes: [
      CameraFramePlaneDto(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        bytesPerRow: 8,
        bytesPerPixel: 4,
        width: 2,
        height: 2,
      ),
    ],
    lens: CameraLensDto.front,
    sensorOrientationDegrees: 270,
    capturedAt: DateTime(2026, 7, 15, 12),
  );
}

final class _FakeCameraDriver implements CameraDriver {
  final StreamController<CameraFrameDto> _frames = StreamController<CameraFrameDto>.broadcast();

  List<CameraDeviceDto> devices = const [
    CameraDeviceDto(
      id: 'rear',
      lens: CameraLensDto.back,
      sensorOrientationDegrees: 90,
    ),
    CameraDeviceDto(
      id: 'front',
      lens: CameraLensDto.front,
      sensorOrientationDegrees: 270,
    ),
  ];
  Exception? listError;
  final List<CameraDeviceDto> enabledDevices = [];

  @override
  Stream<CameraFrameDto> get frames => _frames.stream;

  void addFrame(CameraFrameDto frame) => _frames.add(frame);

  @override
  Future<List<CameraDeviceDto>> listCameras() async {
    final error = listError;
    if (error != null) throw error;
    return devices;
  }

  @override
  Future<void> enable(CameraDeviceDto device) async {
    enabledDevices.add(device);
  }

  @override
  Future<void> disable() async {}

  @override
  Future<void> close() async {
    if (!_frames.isClosed) await _frames.close();
  }
}
