import 'package:flutter/cupertino.dart';
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

final class _AppRouterState extends State<AppRouter> {
  _AppTab _selectedTab = _AppTab.camera;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedTab.index,
              children: const [CameraPage(), AssistantPage()],
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
            onTap: (index) {
              setState(() => _selectedTab = _AppTab.values[index]);
            },
          ),
        ],
      ),
    );
  }
}
