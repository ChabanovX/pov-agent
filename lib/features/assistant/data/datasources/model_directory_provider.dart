import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

const _modelStorageChannelName = 'pov_agent/model_storage';

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

/// Resolves the platform no-backup model directory through the app channel.
final class PlatformModelDirectoryProvider implements ModelDirectoryProvider {
  /// Creates the production provider.
  factory PlatformModelDirectoryProvider() {
    return const PlatformModelDirectoryProvider.withChannel(
      MethodChannel(_modelStorageChannelName),
    );
  }

  /// Creates a provider with an injectable native boundary.
  @visibleForTesting
  const PlatformModelDirectoryProvider.withChannel(this._channel);

  final MethodChannel _channel;

  @override
  Future<Directory> resolve() async {
    final path = await _channel.invokeMethod<String>('resolveDirectory');
    if (path == null || path.trim().isEmpty) {
      throw const FormatException(
        'Model storage channel returned an invalid directory path.',
      );
    }
    return Directory(path);
  }
}
