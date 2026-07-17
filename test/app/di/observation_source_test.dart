import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/app/di/observation_source.dart';

void main() {
  test('parses supported observation sources case-insensitively', () {
    expect(ObservationSource.parse('camera'), ObservationSource.camera);
    expect(ObservationSource.parse(' RECORDED '), ObservationSource.recorded);
  });

  test('rejects an unsupported observation source', () {
    expect(
      () => ObservationSource.parse('video'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
