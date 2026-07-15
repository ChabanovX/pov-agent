import 'dart:async';

import 'package:camera/camera.dart' as plugin;
import 'package:flutter/foundation.dart';
import 'package:some_camera_with_llm/core/logging/app_logger.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/camera_driver.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/camera_frame_sampler.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';
import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';

typedef UtcNow = DateTime Function();

/// Adapts Flutter's camera plugin to the feature's data-source contract.
final class FlutterCameraDriver implements CameraDriver {
  FlutterCameraDriver({
    CameraFrameSampler? sampler,
    UtcNow? utcNow,
  }) : _sampler = sampler ?? CameraFrameSampler(),
       _utcNow = utcNow ?? _defaultUtcNow {
    _framesController = StreamController<CameraFrameDto>.broadcast(
      onListen: _handleFirstFrameListener,
      onCancel: _handleLastFrameListenerCancellation,
    );
  }

  static final AppLogger _logger = AppLogger('FlutterCameraDriver');

  final CameraFrameSampler _sampler;
  final UtcNow _utcNow;
  final Map<String, plugin.CameraDescription> _descriptions = {};
  late final StreamController<CameraFrameDto> _framesController;

  plugin.CameraController? _controller;
  CameraDeviceDto? _activeDevice;
  Future<void> _streamOperation = Future.value();
  bool _enabled = false;
  bool _closed = false;

  @override
  Stream<CameraFrameDto> get frames => _framesController.stream;

  /// Native controller consumed only by app-level preview composition.
  plugin.CameraController get previewController {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera preview requested before the driver was enabled.');
    }
    return controller;
  }

  @override
  Future<List<CameraDeviceDto>> listCameras() async {
    final descriptions = await plugin.availableCameras();
    _descriptions
      ..clear()
      ..addEntries(
        descriptions.map((description) => MapEntry(description.name, description)),
      );

    return descriptions
        .map(
          (description) => CameraDeviceDto(
            id: description.name,
            lens: _lensFromPlugin(description.lensDirection),
            sensorOrientationDegrees: description.sensorOrientation,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> enable(CameraDeviceDto device) async {
    await disable();

    final description = _descriptions[device.id];
    if (description == null) {
      throw plugin.CameraException(
        'cameraNotFound',
        'The selected camera is no longer available.',
      );
    }

    final controller = plugin.CameraController(
      description,
      plugin.ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: _imageFormatForPlatform(),
    );
    _controller = controller;
    _activeDevice = device;

    try {
      await controller.initialize();
      _enabled = true;
      await _scheduleImageStreamReconciliation();
    } catch (_) {
      _enabled = false;
      _controller = null;
      _activeDevice = null;
      await controller.dispose();
      rethrow;
    }
  }

  @override
  Future<void> disable() async {
    final controller = _controller;
    _enabled = false;

    try {
      await _scheduleImageStreamReconciliation();
    } finally {
      _controller = null;
      _activeDevice = null;
      _sampler.reset();
      await controller?.dispose();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await disable();
    await _streamOperation;
    await _framesController.close();
  }

  void _handleFirstFrameListener() {
    unawaited(
      _scheduleImageStreamReconciliation().catchError((Object error, StackTrace stackTrace) {
        if (!_framesController.isClosed) {
          _framesController.addError(error, stackTrace);
        }
      }),
    );
  }

  void _handleLastFrameListenerCancellation() {
    unawaited(
      _scheduleImageStreamReconciliation().catchError((Object error, StackTrace stackTrace) {
        _logger.e(
          'Could not stop the unobserved image stream.',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  Future<void> _scheduleImageStreamReconciliation() {
    final operation = _streamOperation.then((_) => _reconcileImageStream());
    _streamOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _reconcileImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final shouldStream = _enabled && _framesController.hasListener;
    if (shouldStream && !controller.value.isStreamingImages) {
      if (!controller.supportsImageStreaming()) {
        throw plugin.CameraException(
          'imageStreamingUnsupported',
          'The selected camera does not support image streaming.',
        );
      }
      await controller.startImageStream(_handleNativeFrame);
    } else if (!shouldStream && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  void _handleNativeFrame(plugin.CameraImage image) {
    final activeDevice = _activeDevice;
    if (activeDevice == null || _framesController.isClosed) return;

    final frame = _sampler.sample(
      () => CameraFrameDto(
        width: image.width,
        height: image.height,
        format: _formatFromPlugin(image.format.group),
        planes: image.planes
            .map(
              (plane) => CameraFramePlaneDto(
                bytes: plane.bytes,
                bytesPerRow: plane.bytesPerRow,
                bytesPerPixel: plane.bytesPerPixel,
                width: plane.width,
                height: plane.height,
              ),
            )
            .toList(growable: false),
        lens: activeDevice.lens,
        sensorOrientationDegrees: activeDevice.sensorOrientationDegrees,
        capturedAt: _utcNow(),
      ),
    );
    if (frame != null) _framesController.add(frame);
  }
}

DateTime _defaultUtcNow() => DateTime.now().toUtc();

plugin.ImageFormatGroup _imageFormatForPlatform() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => plugin.ImageFormatGroup.yuv420,
    TargetPlatform.iOS => plugin.ImageFormatGroup.bgra8888,
    _ => plugin.ImageFormatGroup.unknown,
  };
}

CameraLensDto _lensFromPlugin(plugin.CameraLensDirection lens) {
  return switch (lens) {
    plugin.CameraLensDirection.back => CameraLensDto.back,
    plugin.CameraLensDirection.front => CameraLensDto.front,
    plugin.CameraLensDirection.external => CameraLensDto.external,
  };
}

CameraFrameFormatDto _formatFromPlugin(plugin.ImageFormatGroup format) {
  return switch (format) {
    plugin.ImageFormatGroup.yuv420 => CameraFrameFormatDto.yuv420,
    plugin.ImageFormatGroup.bgra8888 => CameraFrameFormatDto.bgra8888,
    plugin.ImageFormatGroup.nv21 => CameraFrameFormatDto.nv21,
    plugin.ImageFormatGroup.jpeg => CameraFrameFormatDto.jpeg,
    plugin.ImageFormatGroup.unknown => CameraFrameFormatDto.unknown,
  };
}
