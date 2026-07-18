import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/core/constants/compilation_constants.dart';

const _expectedRecordedVideo = bool.fromEnvironment('EXPECT_RECORDED_VIDEO');

void main() {
  test('reads the recorded-video compilation flag', () {
    expect(CompilationConstants.usesRecordedVideo, _expectedRecordedVideo);
  });
}
