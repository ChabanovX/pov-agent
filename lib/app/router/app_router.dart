import 'dart:async';

import 'package:camera/camera.dart' as plugin;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/assistant/presentation/pages/assistant_page.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_controller.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/flutter_camera_driver.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/camera_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/camera_controller_impl.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';
import 'package:some_camera_with_llm/features/camera/presentation/pages/camera_page.dart';

enum _AppTab { camera, assistant }

final class AppRouter extends StatefulWidget {
  const AppRouter({
    this.cameraController,
    this.cameraPreviewBuilder,
    super.key,
  });

  final CameraController? cameraController;
  final WidgetBuilder? cameraPreviewBuilder;

  @override
  State<AppRouter> createState() => _AppRouterState();
}

final class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  late final FlutterCameraDriver? _cameraDriver;
  late final CameraController _cameraController;
  late final CameraCubit _cameraCubit;
  late final WidgetBuilder _cameraPreviewBuilder;

  _AppTab _selectedTab = _AppTab.camera;
  bool _appForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final injectedController = widget.cameraController;
    if (injectedController == null) {
      final driver = FlutterCameraDriver();
      _cameraDriver = driver;
      _cameraController = CameraControllerImpl(
        driver,
        const CameraFailureMapper(),
      );
      _cameraPreviewBuilder = _buildNativeCameraPreview;
    } else {
      _cameraDriver = null;
      _cameraController = injectedController;
      _cameraPreviewBuilder = widget.cameraPreviewBuilder ?? _buildMissingPreview;
    }

    _cameraCubit = CameraCubit(_cameraController);
    unawaited(_cameraCubit.init());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForegrounded = state == AppLifecycleState.resumed;
    unawaited(
      _cameraCubit.setSurfaceActive(
        active: _appForegrounded && _selectedTab == _AppTab.camera,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cameraCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedTab.index,
              children: [
                BlocProvider.value(
                  value: _cameraCubit,
                  child: CameraPage(previewBuilder: _cameraPreviewBuilder),
                ),
                const AssistantPage(),
              ],
            ),
          ),
          CupertinoTabBar(
            activeColor: CupertinoTheme.of(context).primaryColor,
            backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
            currentIndex: _selectedTab.index,
            inactiveColor: AppColors.light.muted,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.camera),
                label: localizations.cameraTabLabel,
              ),
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.chat_bubble_2),
                label: localizations.assistantTabLabel,
              ),
            ],
            onTap: _selectTab,
          ),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    final selectedTab = _AppTab.values[index];
    if (selectedTab == _selectedTab) return;

    setState(() => _selectedTab = selectedTab);
    unawaited(
      _cameraCubit.setSurfaceActive(
        active: _appForegrounded && selectedTab == _AppTab.camera,
      ),
    );
  }

  Widget _buildNativeCameraPreview(BuildContext context) {
    final controller = _cameraDriver!.previewController;
    return LayoutBuilder(
      builder: (context, constraints) {
        final orientation = controller.value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft || orientation == DeviceOrientation.landscapeRight;
        final previewAspectRatio = landscape ? controller.value.aspectRatio : 1 / controller.value.aspectRatio;
        final viewportAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final previewWidth = previewAspectRatio > viewportAspectRatio
            ? constraints.maxHeight * previewAspectRatio
            : constraints.maxWidth;
        final previewHeight = previewAspectRatio > viewportAspectRatio
            ? constraints.maxHeight
            : constraints.maxWidth / previewAspectRatio;

        return ClipRect(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                width: previewWidth,
                height: previewHeight,
              ),
              child: plugin.CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissingPreview(BuildContext context) {
    return const SizedBox.expand();
  }
}
