import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_frame.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';

abstract final class CameraMapper {
  static CameraLens lensFromDto(CameraLensDto lens) {
    return switch (lens) {
      CameraLensDto.back => CameraLens.back,
      CameraLensDto.front => CameraLens.front,
      CameraLensDto.external => throw const FormatException(
        'External cameras are not supported by the product lens switcher.',
      ),
    };
  }

  static CameraLensDto lensToDto(CameraLens lens) {
    return switch (lens) {
      CameraLens.back => CameraLensDto.back,
      CameraLens.front => CameraLensDto.front,
    };
  }

  static CameraFrame frameFromDto(CameraFrameDto dto) {
    return CameraFrame(
      width: dto.width,
      height: dto.height,
      format: _formatFromDto(dto.format),
      planes: dto.planes
          .map(
            (plane) => CameraFramePlane(
              bytes: plane.bytes,
              bytesPerRow: plane.bytesPerRow,
              bytesPerPixel: plane.bytesPerPixel,
              width: plane.width,
              height: plane.height,
            ),
          )
          .toList(growable: false),
      lens: lensFromDto(dto.lens),
      sensorOrientationDegrees: dto.sensorOrientationDegrees,
      capturedAt: dto.capturedAt,
    );
  }

  static CameraFrameFormat _formatFromDto(CameraFrameFormatDto format) {
    return switch (format) {
      CameraFrameFormatDto.yuv420 => CameraFrameFormat.yuv420,
      CameraFrameFormatDto.bgra8888 => CameraFrameFormat.bgra8888,
      CameraFrameFormatDto.nv21 => CameraFrameFormat.nv21,
      CameraFrameFormatDto.jpeg => CameraFrameFormat.jpeg,
      CameraFrameFormatDto.unknown => CameraFrameFormat.unknown,
    };
  }
}
