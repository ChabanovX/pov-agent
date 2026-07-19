import 'package:flutter/cupertino.dart';
import 'package:pov_agent/app/router/app_router.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';

/// The root widget for POV Agent.
final class PovAgentApp extends StatelessWidget {
  /// Creates the application root.
  const PovAgentApp({super.key});

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
