import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/app/presentation/pages/model_setup_page.dart';
import 'package:pov_agent/core/constants/app_assets.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

void main() {
  testWidgets('renders the canonical ready hierarchy and starts setup', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
    var primaryCalls = 0;
    final state = _state(
      phase: ModelPackPhase.ready,
      items: [
        _item(
          ModelPackItemKind.assistant,
          technicalName: 'Qwen3-0.6B',
          bytes: 512 * 1024 * 1024,
        ),
        _item(
          ModelPackItemKind.vision,
          technicalName: 'YOLO26n',
          phase: ModelPackItemPhase.verified,
        ),
        _item(
          ModelPackItemKind.voice,
          technicalName: 'Piper',
          bytes: 256 * 1024 * 1024,
        ),
        _item(
          ModelPackItemKind.listening,
          technicalName: 'ASR',
          bytes: 256 * 1024 * 1024,
        ),
      ],
    );

    await tester.pumpWidget(
      _TestApp(
        state: state,
        onPrimaryAction: () => primaryCalls += 1,
      ),
    );

    expect(find.text('Set up your on-device AI'), findsOneWidget);
    expect(
      find.text(
        'Download the required models once. '
        'After setup, the assistant works offline.',
      ),
      findsOneWidget,
    );
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Vision'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('1 GB download · 1.5 GB free space required'), findsOneWidget);
    expect(
      find.text('Camera, audio, and conversations are not saved or uploaded.'),
      findsOneWidget,
    );
    final productMark = tester.widget<Image>(
      find.image(AppAssets.povAgentMark),
    );
    expect(productMark.image, AppAssets.povAgentMark);
    expect(find.bySemanticsLabel('POV Agent'), findsOneWidget);

    final scaffold = tester.widget<CupertinoPageScaffold>(
      find.byType(CupertinoPageScaffold),
    );
    expect(scaffold.backgroundColor, AppColors.dark.background);
    final title = tester.widget<Text>(find.text('Set up your on-device AI'));
    expect(title.style?.fontSize, 34);
    expect(title.style?.fontWeight, FontWeight.w700);

    final rows = [
      'assistant',
      'vision',
      'voice',
      'listening',
    ].map((kind) => find.byKey(ValueKey('model-setup-$kind-row'))).toList();
    for (final row in rows) {
      expect(row, findsOneWidget);
    }
    expect(
      tester.getTopLeft(rows[0]).dy,
      lessThan(tester.getTopLeft(rows[1]).dy),
    );
    expect(
      tester
          .getTopLeft(
            find.text(
              'Camera, audio, and conversations are not saved or uploaded.',
            ),
          )
          .dy,
      lessThan(tester.getTopLeft(rows[0]).dy),
    );
    expect(
      tester.getTopLeft(rows[1]).dy,
      lessThan(tester.getTopLeft(rows[2]).dy),
    );
    expect(
      tester.getSemantics(rows[0]).label,
      'Assistant. Qwen3-0.6B. Waiting',
    );

    await tester.tap(find.text('Download models'));
    expect(primaryCalls, 1);
  });

  testWidgets('renders the canonical iPhone setup composition', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);

    await tester.pumpWidget(
      _TestApp(
        state: _state(
          phase: ModelPackPhase.ready,
          items: [
            _item(
              ModelPackItemKind.assistant,
              technicalName: 'Qwen3-0.6B',
              bytes: 512 * 1024 * 1024,
            ),
            _item(
              ModelPackItemKind.vision,
              technicalName: 'YOLO26n',
              phase: ModelPackItemPhase.verified,
            ),
            _item(
              ModelPackItemKind.voice,
              technicalName: 'Piper',
              bytes: 256 * 1024 * 1024,
            ),
            _item(
              ModelPackItemKind.listening,
              technicalName: 'ASR',
              bytes: 256 * 1024 * 1024,
            ),
          ],
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        AppAssets.povAgentMark,
        tester.element(find.byType(ModelSetupPage)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ModelSetupPage),
      matchesGoldenFile('goldens/model_setup_ready.png'),
    );
  });

  testWidgets('shows deterministic transfer progress and cancels', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
    var cancelCalls = 0;
    final state = _state(
      phase: ModelPackPhase.installing,
      items: [
        _item(
          ModelPackItemKind.assistant,
          technicalName: 'Qwen3-0.6B',
          bytes: 100,
          phase: ModelPackItemPhase.downloading,
          progress: 0.5,
        ),
        _item(
          ModelPackItemKind.vision,
          technicalName: 'YOLO26n',
          phase: ModelPackItemPhase.verified,
        ),
        _item(
          ModelPackItemKind.voice,
          technicalName: 'Piper',
          bytes: 200,
          phase: ModelPackItemPhase.verified,
        ),
        _item(
          ModelPackItemKind.listening,
          technicalName: 'ASR',
          bytes: 300,
        ),
      ],
    );

    await tester.pumpWidget(
      _TestApp(
        state: state,
        onCancel: () => cancelCalls += 1,
      ),
    );

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('model-setup-assistant-row')),
          )
          .label,
      'Assistant. Qwen3-0.6B. Downloading 50%',
    );
    expect(find.text('Overall progress'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Cancel download'), findsOneWidget);

    await tester.tap(find.text('Cancel download'));
    expect(cancelCalls, 1);
  });

  testWidgets('uses the retry branch for an offline setup failure', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
    var retryCalls = 0;
    final state = _state(
      phase: ModelPackPhase.failure,
      failure: const NetworkFailure(code: 'model_download_network'),
    );

    await tester.pumpWidget(
      _TestApp(
        state: state,
        onRetry: () => retryCalls += 1,
      ),
    );

    expect(find.text('Connect once to download the models.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    await tester.tap(find.text('Try again'));
    expect(retryCalls, 1);
  });

  testWidgets('keeps storage recovery reachable on a compact iPhone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var checkCalls = 0;
    final state = _state(
      phase: ModelPackPhase.failure,
      availableStorageBytes: 700 * 1024 * 1024,
      failure: const DeviceUnavailableFailure(
        code: 'model_pack_insufficient_storage',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        state: state,
        onCheckAgain: () => checkCalls += 1,
      ),
    );

    expect(
      find.text(
        'Not enough storage. 1.5 GB is required; 700 MB is available. '
        'Manage storage in Settings, then check again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    expect(checkCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the setup action reachable with large Dynamic Type', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var primaryCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        state: _state(phase: ModelPackPhase.ready),
        onPrimaryAction: () => primaryCalls += 1,
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Download models'));
    await tester.tap(find.text('Download models'));
    expect(primaryCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

final class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.state,
    this.onPrimaryAction = _noop,
    this.onCancel = _noop,
    this.onRetry = _noop,
    this.onCheckAgain = _noop,
    this.textScaler,
  });

  final ModelPackState state;
  final VoidCallback onPrimaryAction;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onCheckAgain;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      builder: (context, child) {
        final textScaler = this.textScaler;
        if (textScaler == null) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: ModelSetupPage(
        state: state,
        onPrimaryAction: onPrimaryAction,
        onCancel: onCancel,
        onRetry: onRetry,
        onCheckAgain: onCheckAgain,
      ),
    );
  }
}

void _useIPhone15Viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

ModelPackState _state({
  required ModelPackPhase phase,
  List<ModelPackItemState>? items,
  int? availableStorageBytes,
  AppFailure? failure,
}) {
  return ModelPackState(
    phase: phase,
    items:
        items ??
        [
          _item(
            ModelPackItemKind.assistant,
            technicalName: 'Qwen3-0.6B',
            bytes: 512 * 1024 * 1024,
          ),
          _item(
            ModelPackItemKind.vision,
            technicalName: 'YOLO26n',
            phase: ModelPackItemPhase.verified,
          ),
          _item(
            ModelPackItemKind.voice,
            technicalName: 'Piper',
            bytes: 256 * 1024 * 1024,
          ),
          _item(
            ModelPackItemKind.listening,
            technicalName: 'ASR',
            bytes: 256 * 1024 * 1024,
          ),
        ],
    availableStorageBytes: availableStorageBytes,
    failure: failure,
  );
}

ModelPackItemState _item(
  ModelPackItemKind kind, {
  required String technicalName,
  int bytes = 0,
  ModelPackItemPhase phase = ModelPackItemPhase.waiting,
  double? progress,
}) {
  return ModelPackItemState(
    kind: kind,
    technicalName: technicalName,
    downloadBytes: bytes,
    phase: phase,
    progress: progress,
  );
}

void _noop() {}
