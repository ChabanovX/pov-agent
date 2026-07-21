import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/features/camera/presentation/pages/camera_page.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  testWidgets('renders preview and controls, then powers the camera off', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    await tester.pumpWidget(_TestCameraApp(bloc: bloc));

    expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    expect(
      find.semantics.byLabel('Test observation surface'),
      findsOne,
    );
    expect(find.bySemanticsLabel('Disable camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Switch camera'), findsOneWidget);

    controller.emit(
      ObservationDiagnosticsUpdated(
        ObservationDiagnostics(
          framesPerSecond: 18,
          inferenceTimeMs: 24,
          processingTimeMs: 30,
          frameNumber: 1,
          sampledAt: DateTime.utc(2026, 7, 16),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('FPS 18.0 · Inference 24.0 ms'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Disable camera'));
    await tester.pumpAndSettle();

    expect(find.text('Camera is off.'), findsOneWidget);
    expect(find.text('Enable camera'), findsOneWidget);
    expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    expect(find.text('FPS 18.0 · Inference 24.0 ms'), findsNothing);
    expect(
      find.semantics.byLabel('Test observation surface'),
      findsNothing,
    );

    await tester.tap(find.text('Enable camera'));
    await tester.pumpAndSettle();
    expect(
      find.semantics.byLabel('Test observation surface'),
      findsOne,
    );

    semantics.dispose();
    await _unmountAndSealBloc(tester, bloc);
  });

  testWidgets('shows permission guidance and retries initialization', (
    tester,
  ) async {
    final controller = FakeCameraController(
      initFailure: const PermissionDeniedFailure(),
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.failure,
    );

    await tester.pumpWidget(_TestCameraApp(bloc: bloc));

    expect(
      find.text(
        'Camera access is disabled. Allow camera access in Settings, then retry.',
      ),
      findsOneWidget,
    );

    controller.initFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    expect(controller.initCalls, 2);

    await _unmountAndSealBloc(tester, bloc);
  });

  testWidgets('shows first-download progress over the mounted surface', (
    tester,
  ) async {
    final controller = FakeCameraController(emitModelReadyOnInit: false);
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    await tester.pumpWidget(_TestCameraApp(bloc: bloc));
    controller.emit(const ObservationModelDownloadProgressed(0.37));
    await tester.pump();

    expect(
      find.text('Downloading the YOLO model: 37%'),
      findsOneWidget,
    );
    expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    expect(find.bySemanticsLabel('Disable camera'), findsNothing);

    controller.emit(const ObservationModelReady());
    await tester.pump();

    expect(find.bySemanticsLabel('Disable camera'), findsOneWidget);

    await _unmountAndSealBloc(tester, bloc);
  });

  testWidgets('shows inference failure copy and retries observation', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    await tester.pumpWidget(_TestCameraApp(bloc: bloc));
    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );
    await tester.pump();

    expect(find.text('The frame could not be analyzed.'), findsOneWidget);
    expect(find.text('The YOLO model could not be prepared.'), findsNothing);
    expect(find.bySemanticsLabel('Disable camera'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(controller.retryObservationCalls, 1);
    expect(find.text('The frame could not be analyzed.'), findsNothing);
    expect(find.bySemanticsLabel('Disable camera'), findsOneWidget);

    await _unmountAndSealBloc(tester, bloc);
  });

  testWidgets('keeps inference failure retryable when retry fails', (
    tester,
  ) async {
    final controller = FakeCameraController(
      retryObservationFailure: const DeviceUnavailableFailure(
        code: 'observation_retry_failed',
      ),
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    await tester.pumpWidget(_TestCameraApp(bloc: bloc));
    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('The frame could not be analyzed.'), findsOneWidget);
    expect(find.bySemanticsLabel('Disable camera'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.retryObservationCalls, 2);
    expect(find.text('The frame could not be analyzed.'), findsOneWidget);

    await _unmountAndSealBloc(tester, bloc);
  });
}

final class _TestCameraApp extends StatelessWidget {
  const _TestCameraApp({required this.bloc});

  final CameraBloc bloc;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: BlocProvider.value(
        value: bloc,
        child: const CameraPage(
          surfaceBuilder: buildTestObservationSurface,
        ),
      ),
    );
  }
}

Future<CameraState> _waitForState(
  CameraBloc bloc,
  bool Function(CameraState state) predicate,
) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate);
}

Future<void> _unmountAndSealBloc(
  WidgetTester tester,
  CameraBloc bloc,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The fake-async widget listener receives the stream's done event only while
  // the test zone unwinds. Awaiting close here would deadlock that delivery.
  unawaited(bloc.close());
}
