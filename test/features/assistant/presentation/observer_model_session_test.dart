import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_model_session.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../../../support/fake_assistant_runtime.dart';

void main() {
  test('loads llama runtime only after foreground preparation is requested', () async {
    final store = FakeAssistantModelStore(
      current: QwenModelStoreState.ready(testQwenArtifact),
    );
    final generator = _ModelSessionGenerator();
    final updates = <ObserverModelUpdate>[];
    final session = ObserverModelSession(
      modelStore: store,
      commentGenerator: generator,
      onUpdate: updates.add,
    )..activate();

    expect(session.current.phase, ModelStorePhase.loading);
    expect(generator.loadCalls, 0);

    session.requestPreparation();
    await _waitFor(() => updates.whereType<ObserverModelPreparationCompleted>().isNotEmpty);

    expect(store.prepareCalls, 0);
    expect(generator.loadCalls, 1);
    expect(session.current.phase, ModelStorePhase.ready);
    expect(
      updates.whereType<ObserverModelStateChanged>().last.state.phase,
      ModelStorePhase.loading,
    );
    expect(
      updates.whereType<ObserverModelPreparationCompleted>().single.result,
      isA<AppSuccess<VerifiedModelArtifact>>(),
    );

    await session.close();
    await store.close();
  });

  test('normalizes runtime activation failure after artifact verification', () async {
    const failure = DeviceUnavailableFailure(code: 'test_llama_load_failed');
    final store = FakeAssistantModelStore();
    final generator = _ModelSessionGenerator(loadResult: const AppError(failure));
    final updates = <ObserverModelUpdate>[];
    final session =
        ObserverModelSession(
            modelStore: store,
            commentGenerator: generator,
            onUpdate: updates.add,
          )
          ..activate()
          ..requestPreparation();
    await _waitFor(() => updates.whereType<ObserverModelPreparationCompleted>().isNotEmpty);

    expect(
      updates.whereType<ObserverModelPreparationCompleted>().single.result,
      isA<AppError<VerifiedModelArtifact>>().having(
        (error) => error.failure,
        'failure',
        same(failure),
      ),
    );
    expect(session.current.phase, ModelStorePhase.loading);

    await session.suspend();
    expect(store.suspendCalls, 1);
    expect(generator.unloadCalls, 1);
    await session.close();
    await store.close();
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected the model session to settle.');
}

final class _ModelSessionGenerator implements CommentGenerator {
  _ModelSessionGenerator({
    this.loadResult = const AppSuccess<void>(null),
  });

  final AppResult<void> loadResult;
  int loadCalls = 0;
  int unloadCalls = 0;

  @override
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact) async {
    loadCalls += 1;
    return loadResult;
  }

  @override
  Future<AppResult<GenerationHandle>> generate(
    CommentGenerationRequest request,
  ) async {
    return const AppError(
      UnexpectedFailure(code: 'generation_not_used'),
    );
  }

  @override
  Future<void> unload() async {
    unloadCalls += 1;
  }

  @override
  Future<void> close() async {}
}
