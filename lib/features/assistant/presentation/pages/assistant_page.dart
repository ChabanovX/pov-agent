import 'package:flutter/cupertino.dart';

import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';

/// The placeholder page for the assistant tab.
final class AssistantPage extends StatelessWidget {
  /// Creates the assistant page.
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(localizations.assistantTabLabel),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Text(localizations.assistantPlaceholderTitle),
        ),
      ),
    );
  }
}
