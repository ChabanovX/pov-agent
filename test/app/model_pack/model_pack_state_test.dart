import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';

void main() {
  test('overall progress is weighted by downloadable bytes', () {
    final state = ModelPackState(
      phase: ModelPackPhase.installing,
      items: [
        _item(
          kind: ModelPackItemKind.assistant,
          bytes: 100,
          phase: ModelPackItemPhase.downloading,
          progress: 0.5,
        ),
        _item(
          kind: ModelPackItemKind.vision,
          bytes: 0,
          phase: ModelPackItemPhase.verified,
        ),
        _item(
          kind: ModelPackItemKind.voice,
          bytes: 200,
          phase: ModelPackItemPhase.verified,
        ),
        _item(
          kind: ModelPackItemKind.listening,
          bytes: 300,
          phase: ModelPackItemPhase.waiting,
        ),
      ],
    );

    expect(state.totalDownloadBytes, 600);
    expect(state.overallProgress, closeTo(250 / 600, 0.000001));
    expect(state.activeItem?.kind, ModelPackItemKind.assistant);
  });

  test('replacing a row preserves order and makes the list immutable', () {
    final assistant = _item(
      kind: ModelPackItemKind.assistant,
      bytes: 100,
      phase: ModelPackItemPhase.waiting,
    );
    final vision = _item(
      kind: ModelPackItemKind.vision,
      bytes: 0,
      phase: ModelPackItemPhase.verified,
    );
    final state = ModelPackState(
      phase: ModelPackPhase.ready,
      items: [assistant, vision],
    );

    final replacement = assistant.withStatus(
      phase: ModelPackItemPhase.downloading,
      progress: 0.25,
    );
    final next = state.replaceItem(ModelPackItemKind.assistant, replacement);

    expect(
      next.items.map((item) => item.kind),
      [ModelPackItemKind.assistant, ModelPackItemKind.vision],
    );
    expect(next.item(ModelPackItemKind.assistant), same(replacement));
    expect(() => next.items.add(assistant), throwsUnsupportedError);
  });
}

ModelPackItemState _item({
  required ModelPackItemKind kind,
  required int bytes,
  required ModelPackItemPhase phase,
  double? progress,
}) {
  return ModelPackItemState(
    kind: kind,
    technicalName: '${kind.name}-model',
    downloadBytes: bytes,
    phase: phase,
    progress: progress,
  );
}
