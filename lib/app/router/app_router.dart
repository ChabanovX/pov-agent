import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/pages/assistant_page.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/pages/camera_page.dart';
import 'package:pov_agent/features/camera/presentation/widgets/recorded_observation_surface.dart';
import 'package:pov_agent/features/camera/presentation/widgets/yolo_observation_surface.dart';

enum _AppTab { camera, assistant }

/// The tab router that coordinates observation-surface activity.
final class AppRouter extends StatefulWidget {
  /// Creates the application router.
  const AppRouter({
    this.observationSurfaceBuilder,
    super.key,
  });

  /// Overrides production observation-surface composition in tests.
  @visibleForTesting
  final WidgetBuilder? observationSurfaceBuilder;

  @override
  State<AppRouter> createState() => _AppRouterState();
}

final class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  late final AppRuntime _runtime;
  late WidgetBuilder _observationSurfaceBuilder;

  _AppTab _selectedTab = _AppTab.camera;
  bool _appForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtime = appDependencies<AppRuntime>();
    _observationSurfaceBuilder = widget.observationSurfaceBuilder ?? _resolveObservationSurfaceBuilder();
  }

  @override
  void didUpdateWidget(AppRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(
      oldWidget.observationSurfaceBuilder,
      widget.observationSurfaceBuilder,
    )) {
      return;
    }
    _observationSurfaceBuilder = widget.observationSurfaceBuilder ?? _resolveObservationSurfaceBuilder();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForegrounded = state == AppLifecycleState.resumed;
    final cameraBloc = _runtime.cameraBloc;
    if (cameraBloc.isClosed) return;
    cameraBloc.add(
      CameraSurfaceActivityChanged(
        active: _appForegrounded && _selectedTab == _AppTab.camera,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                  value: _runtime.cameraBloc,
                  child: CameraPage(
                    surfaceBuilder: _observationSurfaceBuilder,
                  ),
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
    final cameraBloc = _runtime.cameraBloc;
    if (cameraBloc.isClosed) return;
    cameraBloc.add(
      CameraSurfaceActivityChanged(
        active: _appForegrounded && selectedTab == _AppTab.camera,
      ),
    );
  }

  WidgetBuilder _resolveObservationSurfaceBuilder() {
    if (CompilationConstants.usesRecordedVideo) {
      final frameSource = appDependencies<RecordedObservationFrameSource>();
      return (_) => RecordedObservationSurface(frameSource: frameSource);
    }

    final observationAdapter = appDependencies<YoloObservationAdapter>();
    return (_) => YoloObservationSurface(
      configuration: observationAdapter.configuration,
      surfaceRevision: observationAdapter.surfaceRevision,
      desiredLens: () => observationAdapter.desiredLens,
      viewController: observationAdapter.viewController,
      onResults: observationAdapter.handleResults,
      onPerformance: observationAdapter.handlePerformance,
      onModelLoaded: observationAdapter.handleModelLoaded,
      onModelError: observationAdapter.handleModelError,
    );
  }
}
