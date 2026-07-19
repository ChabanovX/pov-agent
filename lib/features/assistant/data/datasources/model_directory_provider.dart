import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves the directory that owns downloaded model artifacts.
// The effectful filesystem seam must remain injectable in boundary tests.
// ignore: one_member_abstracts
abstract interface class ModelDirectoryProvider {
  /// Returns the directory reserved for model files.
  Future<Directory> resolve();
}

/// Stores models below the platform application-support directory.
final class ApplicationSupportModelDirectoryProvider implements ModelDirectoryProvider {
  /// Creates the production model-directory provider.
  const ApplicationSupportModelDirectoryProvider();

  @override
  Future<Directory> resolve() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(
      '${supportDirectory.path}${Platform.pathSeparator}models',
    );
  }
}
