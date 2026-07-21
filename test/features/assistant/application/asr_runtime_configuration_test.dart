import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/asr_runtime_configuration.dart';

void main() {
  test('compares every native execution and endpoint setting', () {
    expect(_configuration(), _configuration());
    expect(
      _configuration(maxPendingAudioChunks: 9),
      isNot(_configuration()),
    );
  });

  test('rejects an invalid audio queue policy', () {
    expect(
      () => _configuration(maxPendingAudioChunks: 0),
      throwsAssertionError,
    );
  });
}

AsrRuntimeConfiguration _configuration({int maxPendingAudioChunks = 8}) {
  return AsrRuntimeConfiguration(
    provider: 'cpu',
    threadCount: 2,
    sampleRateHz: 16000,
    featureDimension: 80,
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
    rule1MinTrailingSilence: const Duration(milliseconds: 2400),
    rule2MinTrailingSilence: const Duration(milliseconds: 1200),
    maxUtteranceDuration: const Duration(seconds: 15),
    debug: false,
    maxPendingAudioChunks: maxPendingAudioChunks,
  );
}
