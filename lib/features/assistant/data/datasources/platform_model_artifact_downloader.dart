import 'dart:io';

import 'package:pov_agent/features/assistant/data/datasources/ios_background_model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';

/// Creates the production transport selected by the host platform.
///
/// iOS delegates model transfers to a persistent background URLSession. Other
/// platforms retain the foreground HTTP implementation until their native
/// background-transfer owner is introduced.
ModelArtifactDownloader createPlatformModelArtifactDownloader() {
  if (Platform.isIOS) return IosBackgroundModelArtifactDownloader();
  return HttpModelArtifactDownloader();
}
