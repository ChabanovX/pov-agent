import 'dart:async';

import 'package:some_camera_with_llm/core/errors/failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_controller.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/camera_driver.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/camera_mapper.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_frame.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

final class CameraControllerImpl implements CameraController {
  CameraControllerImpl(this._driver, this._failureMapper);

  final CameraDriver _driver;
  final FailureMapper _failureMapper;
  List<CameraDeviceDto> _devices = const [];

  @override
  Stream<AppResult<CameraFrame>> get frames {
    return _driver.frames.transform(
      StreamTransformer<CameraFrameDto, AppResult<CameraFrame>>.fromHandlers(
        handleData: (frame, sink) {
          sink.add(AppSuccess(CameraMapper.frameFromDto(frame)));
        },
        handleError: (error, stackTrace, sink) {
          sink.add(AppError(_failureMapper.map(error, stackTrace)));
        },
      ),
    );
  }

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    try {
      final devices = await _driver.listCameras();
      _devices = devices.where((device) => device.lens != CameraLensDto.external).toList(growable: false);
      if (_devices.isEmpty) {
        return const AppError(
          DeviceUnavailableFailure(message: 'No supported camera was found.'),
        );
      }

      final availableLenses = _devices
          .map((device) => CameraMapper.lensFromDto(device.lens))
          .toSet()
          .toList(growable: false);
      final preferredLens = availableLenses.contains(CameraLens.back) ? CameraLens.back : CameraLens.front;

      return AppSuccess(
        CameraCapabilities(
          availableLenses: availableLenses,
          preferredLens: preferredLens,
        ),
      );
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<void>> enable(CameraLens lens) async {
    try {
      final lensDto = CameraMapper.lensToDto(lens);
      final device = _devices.where((candidate) => candidate.lens == lensDto).firstOrNull;
      if (device == null) {
        return AppError(
          DeviceUnavailableFailure(message: 'The ${lens.name} camera is unavailable.'),
        );
      }

      await _driver.enable(device);
      return const AppSuccess<void>(null);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<void>> disable() async {
    try {
      await _driver.disable();
      return const AppSuccess<void>(null);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<void> close() => _driver.close();
}
