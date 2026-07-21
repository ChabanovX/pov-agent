import 'package:flutter/cupertino.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/router/app_router.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';

const _productLocale = Locale('en', 'US');

/// The root widget for POV Agent.
final class PovAgentApp extends StatelessWidget {
  /// Creates the application root.
  const PovAgentApp({
    this.observationSurfaceBuilder,
    this.runtime,
    this.modelPackController,
    super.key,
  });

  /// Overrides production observation-surface composition in tests.
  @visibleForTesting
  final WidgetBuilder? observationSurfaceBuilder;

  /// Overrides the process runtime in focused app tests.
  @visibleForTesting
  final AppRuntime? runtime;

  /// Overrides the model setup owner in focused app tests.
  @visibleForTesting
  final ModelPackController? modelPackController;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: _productLocale,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: AppRouter(
        observationSurfaceBuilder: observationSurfaceBuilder,
        runtime: runtime,
        modelPackController: modelPackController,
      ),
    );
  }
}
