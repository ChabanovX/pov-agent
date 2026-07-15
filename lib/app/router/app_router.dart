import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';
import 'package:some_camera_with_llm/features/assistant/presentation/pages/assistant_page.dart';
import 'package:some_camera_with_llm/features/camera/presentation/pages/camera_page.dart';

enum _AppTab { camera, assistant }

final class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

final class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  late final AppRuntime _runtime;

  _AppTab _selectedTab = _AppTab.camera;
  bool _appForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtime = appDependencies<AppRuntime>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForegrounded = state == AppLifecycleState.resumed;
    unawaited(
      _runtime.cameraCubit.setSurfaceActive(
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
                  value: _runtime.cameraCubit,
                  child: CameraPage(
                    previewBuilder: (_) => _runtime.cameraPreview,
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
    unawaited(
      _runtime.cameraCubit.setSurfaceActive(
        active: _appForegrounded && selectedTab == _AppTab.camera,
      ),
    );
  }
}
