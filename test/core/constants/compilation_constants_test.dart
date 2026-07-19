import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';

const _expectedRecordedVideo = bool.fromEnvironment('EXPECT_RECORDED_VIDEO');

void main() {
  test('reads the recorded-video compilation flag', () {
    expect(CompilationConstants.usesRecordedVideo, _expectedRecordedVideo);
  });
}
