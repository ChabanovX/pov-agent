import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/app/presentation/pages/assistant_camera_page.dart';
import 'package:pov_agent/app/presentation/pages/model_setup_page.dart';
import 'package:pov_agent/app/presentation/pages/settings_page.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/presentation/widgets/recorded_observation_surface.dart';
import 'package:pov_agent/features/camera/presentation/widgets/yolo_observation_surface.dart';

enum _AppTab { assistant, settings }

/// Owns the mandatory setup gate and the two-destination application shell.
final class AppRouter extends StatefulWidget {
  /// Creates the application router.
  const AppRouter({
    this.observationSurfaceBuilder,
    this.runtime,
    this.modelPackController,
    super.key,
  });

  /// Overrides production observation-surface composition in tests.
  @visibleForTesting
  final WidgetBuilder? observationSurfaceBuilder;

  /// Overrides the process runtime in focused router tests.
  @visibleForTesting
  final AppRuntime? runtime;

  /// Overrides the model setup owner in focused router tests.
  @visibleForTesting
  final ModelPackController? modelPackController;

  @override
  State<AppRouter> createState() => _AppRouterState();
}

final class _AppRouterState extends State<AppRouter> {
  late final AppRuntime _runtime;
  late final ModelPackController _modelPackController;
  late final StreamSubscription<ModelPackState> _modelPackSubscription;
  late WidgetBuilder _observationSurfaceBuilder;
  late ModelPackState _modelPackState;

  _AppTab _selectedTab = _AppTab.assistant;
  Future<void>? _runtimeStartTask;
  Object? _runtimeStartFailure;
  var _runtimeReady = false;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? appDependencies<AppRuntime>();
    _modelPackController = widget.modelPackController ?? appDependencies<ModelPackController>();
    _modelPackState = _modelPackController.current;
    _observationSurfaceBuilder = widget.observationSurfaceBuilder ?? _resolveObservationSurfaceBuilder();
    _modelPackSubscription = _modelPackController.states.listen(
      _onModelPackState,
    );
    if (_modelPackState.isComplete) {
      _startRuntime();
    } else {
      unawaited(_modelPackController.start());
    }
  }

  @override
  void didUpdateWidget(AppRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.runtime, widget.runtime) &&
          identical(
            oldWidget.modelPackController,
            widget.modelPackController,
          ),
      'Process-owned router dependencies cannot change in place.',
    );
    if (identical(
      oldWidget.observationSurfaceBuilder,
      widget.observationSurfaceBuilder,
    )) {
      return;
    }
    _observationSurfaceBuilder = widget.observationSurfaceBuilder ?? _resolveObservationSurfaceBuilder();
  }

  @override
  void dispose() {
    unawaited(_modelPackSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_modelPackState.isComplete) {
      return ModelSetupPage(
        state: _modelPackState,
        onPrimaryAction: () => unawaited(_modelPackController.install()),
        onCancel: () => unawaited(_modelPackController.cancel()),
        onRetry: () => unawaited(_modelPackController.install()),
        onCheckAgain: () => unawaited(_modelPackController.checkAgain()),
      );
    }
    if (!_runtimeReady) {
      return _RuntimeStartingPage(failure: _runtimeStartFailure);
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _runtime.cameraBloc),
        BlocProvider.value(value: _runtime.observerBloc),
      ],
      child: ValueListenableBuilder<bool>(
        valueListenable: _runtime.privacyCoverVisible,
        builder: (context, privacyCoverVisible, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CupertinoPageScaffold(
                backgroundColor: AppColors.dark.background,
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _selectedTab.index,
                        children: [
                          AssistantCameraPage(
                            surfaceBuilder: _observationSurfaceBuilder,
                          ),
                          SettingsPage(modelPackState: _modelPackState),
                        ],
                      ),
                    ),
                    ColoredBox(
                      color: AppColors.dark.surface,
                      child: SafeArea(
                        top: false,
                        child: CupertinoTabBar(
                          currentIndex: _selectedTab.index,
                          activeColor: AppColors.dark.textPrimary,
                          inactiveColor: AppColors.dark.textSecondary,
                          backgroundColor: AppColors.dark.surface,
                          border: Border(
                            top: BorderSide(
                              color: AppColors.dark.border,
                              width: AppSizes.regular.hairlineWidth,
                            ),
                          ),
                          items: [
                            BottomNavigationBarItem(
                              icon: const Icon(CupertinoIcons.sparkles),
                              label: AppLocalizations.of(
                                context,
                              ).assistantTabLabel,
                            ),
                            BottomNavigationBarItem(
                              icon: const Icon(CupertinoIcons.gear),
                              label: AppLocalizations.of(
                                context,
                              ).settingsTabLabel,
                            ),
                          ],
                          onTap: _selectTab,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (privacyCoverVisible)
                ColoredBox(
                  key: const ValueKey('app-privacy-cover'),
                  color: AppColors.dark.background,
                ),
            ],
          );
        },
      ),
    );
  }

  void _onModelPackState(ModelPackState state) {
    if (!mounted) return;
    setState(() => _modelPackState = state);
    if (state.isComplete) _startRuntime();
  }

  void _startRuntime() {
    if (_runtimeStartTask != null) return;
    late final Future<void> task;
    task = _runtime.start().then<void>(
      (_) {
        if (!mounted || !identical(_runtimeStartTask, task)) return;
        setState(() {
          _runtimeReady = true;
          _runtimeStartFailure = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || !identical(_runtimeStartTask, task)) return;
        setState(() => _runtimeStartFailure = error);
      },
    );
    _runtimeStartTask = task;
  }

  void _selectTab(int index) {
    final selectedTab = _AppTab.values[index];
    if (selectedTab == _selectedTab) return;
    setState(() => _selectedTab = selectedTab);
    unawaited(
      _runtime.setAssistantDestinationActive(
        active: selectedTab == _AppTab.assistant,
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

final class _RuntimeStartingPage extends StatelessWidget {
  const _RuntimeStartingPage({required this.failure});

  final Object? failure;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.dark.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.regular.insetLg,
            child: failure == null
                ? const CupertinoActivityIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: AppColors.dark.danger,
                        size: AppSizes.regular.sheetIcon,
                      ),
                      Padding(
                        padding: AppSpacing.regular.topComponent,
                        child: Text(
                          localizations.runtimeStartFailureMessage,
                          textAlign: TextAlign.center,
                          style: AppTypography.regular.body.copyWith(
                            color: AppColors.dark.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
