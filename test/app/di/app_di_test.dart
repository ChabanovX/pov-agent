import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await appDependencies.reset(dispose: false);
  });

  test('registers the selected adapter under its surface contracts', () async {
    final runtime = configureDependencies();
    try {
      final controller = appDependencies<ObservationController>();
      expect(
        appDependencies<SceneSource>(),
        same(runtime.sceneSession),
      );
      expect(
        appDependencies<ObserverBloc>(),
        same(runtime.observerBloc),
      );
      expect(
        appDependencies<QwenModelStore>(),
        same(runtime.modelStore),
      );
      expect(
        appDependencies<CommentGenerator>(),
        same(runtime.commentGenerator),
      );
      expect(
        appDependencies<SpeechSynthesizer>(),
        same(runtime.speechSynthesizer),
      );
      expect(runtime.observerBloc.state.started, isFalse);
      expect(runtime.modelStore.current.phase, ModelStorePhase.idle);

      if (CompilationConstants.usesRecordedVideo) {
        final adapter = appDependencies<RecordedObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies<RecordedObservationFrameSource>(),
          same(adapter),
        );
        expect(
          appDependencies.isRegistered<YoloObservationAdapter>(),
          isFalse,
        );
      } else {
        final adapter = appDependencies<YoloObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies.isRegistered<RecordedObservationAdapter>(),
          isFalse,
        );
        expect(
          appDependencies.isRegistered<RecordedObservationFrameSource>(),
          isFalse,
        );
      }
    } finally {
      await runtime.close();
    }
  });
}
