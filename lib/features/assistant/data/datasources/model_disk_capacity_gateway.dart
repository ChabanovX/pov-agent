import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

const _modelStorageChannelName = 'pov_agent/model_storage';

/// Reads filesystem capacity for the volume containing the model cache.
// The platform boundary is injectable even though it exposes one operation.
// ignore: one_member_abstracts
abstract interface class ModelDiskCapacityGateway {
  /// Returns currently available bytes for [directoryPath].
  Future<int> availableBytes(String directoryPath);
}

/// Reads platform filesystem capacity through the app-owned method channel.
final class MethodChannelModelDiskCapacityGateway implements ModelDiskCapacityGateway {
  /// Creates a gateway using the production model-storage channel.
  factory MethodChannelModelDiskCapacityGateway() {
    return const MethodChannelModelDiskCapacityGateway.withChannel(
      MethodChannel(_modelStorageChannelName),
    );
  }

  /// Creates a gateway with an injectable platform channel.
  @visibleForTesting
  const MethodChannelModelDiskCapacityGateway.withChannel(this._channel);

  final MethodChannel _channel;

  @override
  Future<int> availableBytes(String directoryPath) async {
    final result = await _channel.invokeMethod<Object?>('availableBytes', {
      'directoryPath': directoryPath,
    });
    if (result case final int bytes when bytes >= 0) return bytes;
    throw const FormatException(
      'Model storage channel returned invalid available bytes.',
    );
  }
}
