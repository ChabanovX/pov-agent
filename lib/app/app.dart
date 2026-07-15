import 'package:flutter/cupertino.dart';
import 'package:some_camera_with_llm/app/router/app_router.dart';
import 'package:some_camera_with_llm/core/design_system/app_theme.dart';
import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';

final class SomeCameraWithLlmApp extends StatelessWidget {
  const SomeCameraWithLlmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: const AppRouter(),
    );
  }
}
