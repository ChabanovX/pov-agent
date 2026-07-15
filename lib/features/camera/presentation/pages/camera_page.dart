import 'package:flutter/cupertino.dart';

import 'package:some_camera_with_llm/core/l10n/app_localizations.dart';

final class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(localizations.cameraTabLabel),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Text(localizations.cameraPlaceholderTitle),
        ),
      ),
    );
  }
}
