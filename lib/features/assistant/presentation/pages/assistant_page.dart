import 'package:flutter/cupertino.dart';

import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';

final class AssistantPage extends StatelessWidget {
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
