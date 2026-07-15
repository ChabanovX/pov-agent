import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/core/design_system/app_theme.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';
import 'package:some_camera_with_llm/features/camera/presentation/pages/camera_page.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  testWidgets('renders preview and controls, then powers the camera off', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final cubit = CameraCubit(controller);
    await cubit.init();

    await tester.pumpWidget(_TestCameraApp(cubit: cubit));

    expect(find.byKey(testCameraPreviewKey), findsOneWidget);
    expect(find.bySemanticsLabel('Disable camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Switch camera'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Disable camera'));
    await tester.pumpAndSettle();

    expect(find.text('Camera is off.'), findsOneWidget);
    expect(find.text('Enable camera'), findsOneWidget);

    await cubit.close();
  });

  testWidgets('shows permission guidance and retries initialization', (
    tester,
  ) async {
    final controller = FakeCameraController(
      initFailure: const PermissionDeniedFailure(),
    );
    final cubit = CameraCubit(controller);
    await cubit.init();

    await tester.pumpWidget(_TestCameraApp(cubit: cubit));

    expect(
      find.text(
        'Camera access is disabled. Allow camera access in Settings, then retry.',
      ),
      findsOneWidget,
    );

    controller.initFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(testCameraPreviewKey), findsOneWidget);
    expect(controller.initCalls, 2);

    await cubit.close();
  });
}

final class _TestCameraApp extends StatelessWidget {
  const _TestCameraApp({required this.cubit});

  final CameraCubit cubit;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: BlocProvider.value(
        value: cubit,
        child: const CameraPage(previewBuilder: buildTestCameraPreview),
      ),
    );
  }
}
