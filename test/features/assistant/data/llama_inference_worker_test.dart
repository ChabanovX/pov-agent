import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';

void main() {
  test('retries native destroy before disposing worker ownership', () async {
    final firstFailure = StateError('native destroy failed');
    var nativeCloseCalls = 0;
    var disposeCalls = 0;
    final shutdown = LlamaWorkerShutdownCoordinator(
      closeNative: () async {
        nativeCloseCalls += 1;
        if (nativeCloseCalls == 1) throw firstFailure;
      },
      dispose: () async {
        disposeCalls += 1;
      },
    );

    await expectLater(shutdown.close(), throwsA(same(firstFailure)));

    expect(shutdown.isClosing, isFalse);
    expect(shutdown.isClosed, isFalse);
    expect(nativeCloseCalls, 1);
    expect(disposeCalls, 0);

    await shutdown.close();
    await shutdown.close();

    expect(shutdown.isClosing, isFalse);
    expect(shutdown.isClosed, isTrue);
    expect(nativeCloseCalls, 2);
    expect(disposeCalls, 1);
  });
}
