import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  const mapper = YoloFailureMapper();

  test('maps transport connectivity errors to network failures', () {
    final failure = mapper.map(
      const SocketException('offline'),
      StackTrace.empty,
    );

    expect(failure, isA<NetworkFailure>());
  });

  test('maps native camera permission errors to permission failures', () {
    final failure = mapper.map(
      PlatformException(
        code: 'CameraAccessDenied',
        message: 'Permission denied.',
      ),
      StackTrace.empty,
    );

    expect(failure, isA<PermissionDeniedFailure>());
  });

  test('distinguishes model-download failures from local load failures', () {
    final downloadFailure = mapper.map(
      ModelLoadingException('Failed to download model.'),
      StackTrace.empty,
    );
    final localFailure = mapper.map(
      ModelLoadingException('Model metadata is invalid.'),
      StackTrace.empty,
    );

    expect(downloadFailure, isA<NetworkFailure>());
    expect(downloadFailure.code, 'model_download');
    expect(localFailure, isA<UnexpectedFailure>());
    expect(localFailure.code, 'model_loading');
  });
}
