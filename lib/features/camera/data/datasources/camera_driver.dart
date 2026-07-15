import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';

abstract interface class CameraDriver {
  Stream<CameraFrameDto> get frames;

  Future<List<CameraDeviceDto>> listCameras();

  Future<void> enable(CameraDeviceDto device);

  Future<void> disable();

  Future<void> close();
}
