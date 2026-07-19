import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';

const _expectedRecordedVideo = bool.fromEnvironment('EXPECT_RECORDED_VIDEO');
const _expectInvalidRecordedVideo = bool.fromEnvironment(
  'EXPECT_INVALID_RECORDED_VIDEO',
);

void main() {
  test('reads the recorded-video compilation flag', () {
    if (_expectInvalidRecordedVideo) {
      expect(
        () => CompilationConstants.usesRecordedVideo,
        throwsFormatException,
      );
      return;
    }
    expect(CompilationConstants.usesRecordedVideo, _expectedRecordedVideo);
  });
}
