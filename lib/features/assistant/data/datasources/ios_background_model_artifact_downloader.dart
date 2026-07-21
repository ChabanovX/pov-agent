import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';

const _methodChannelName = 'pov_agent/model_downloads';
const _eventChannelName = 'pov_agent/model_download_progress';

/// Immutable request understood by the iOS background-transfer channel.
final class IosBackgroundModelTransferRequest {
  /// Creates a transfer request with a process-independent identity.
  IosBackgroundModelTransferRequest({
    required this.source,
    required this.destinationPath,
    required this.expectedBytes,
  }) : transferId = _transferIdFor(
         source: source,
         destinationPath: destinationPath,
         expectedBytes: expectedBytes,
       );

  /// Stable identity used to reattach to a URLSession task after relaunch.
  final String transferId;

  /// Pinned remote artifact URL.
  final Uri source;

  /// Caller-owned staging path populated only with a complete download.
  final String destinationPath;

  /// Pinned byte count from the model manifest.
  final int expectedBytes;

  /// Encodes this request for the native method channel.
  Map<String, Object> toPlatformArguments() {
    return {
      'transferId': transferId,
      'sourceUrl': source.toString(),
      'destinationPath': destinationPath,
      'expectedBytes': expectedBytes,
    };
  }
}

/// Confirmed native progress for one persistent background transfer.
final class IosBackgroundModelTransferProgress {
  /// Creates a progress snapshot received from URLSession.
  const IosBackgroundModelTransferProgress({
    required this.transferId,
    required this.receivedBytes,
    required this.expectedBytes,
  });

  /// Stable transfer identity.
  final String transferId;

  /// Bytes durably owned by the URLSession download task.
  final int receivedBytes;

  /// Pinned total byte count.
  final int expectedBytes;
}

/// Completion returned after native code publishes the staging file.
final class IosBackgroundModelTransferCompletion {
  /// Creates a successful transfer completion.
  const IosBackgroundModelTransferCompletion({
    required this.transferId,
    required this.receivedBytes,
  });

  /// Stable transfer identity.
  final String transferId;

  /// Final byte count moved to the caller-owned staging path.
  final int receivedBytes;
}

/// Injectable bridge between the Dart downloader and iOS URLSession.
abstract interface class IosBackgroundModelTransferBridge {
  /// Native progress, including the reconciled count after reattachment.
  Stream<IosBackgroundModelTransferProgress> get progressEvents;

  /// Starts a new task or attaches to the matching persistent task.
  Future<IosBackgroundModelTransferCompletion> start(
    IosBackgroundModelTransferRequest request,
  );

  /// Cancels a task and removes its unverified transfer state.
  Future<void> cancel(String transferId);
}

/// Method/event-channel implementation of the iOS transfer bridge.
final class MethodChannelIosBackgroundModelTransferBridge implements IosBackgroundModelTransferBridge {
  /// Creates the production bridge.
  factory MethodChannelIosBackgroundModelTransferBridge() {
    return MethodChannelIosBackgroundModelTransferBridge.withChannels(
      const MethodChannel(_methodChannelName),
      rawProgressEvents: const EventChannel(
        _eventChannelName,
      ).receiveBroadcastStream(),
    );
  }

  /// Creates a bridge with injectable channel traffic for boundary tests.
  @visibleForTesting
  MethodChannelIosBackgroundModelTransferBridge.withChannels(
    this._methodChannel, {
    required Stream<Object?> rawProgressEvents,
  }) : _progressEvents = rawProgressEvents.map(_parseProgress).asBroadcastStream();

  final MethodChannel _methodChannel;
  final Stream<IosBackgroundModelTransferProgress> _progressEvents;

  @override
  Stream<IosBackgroundModelTransferProgress> get progressEvents => _progressEvents;

  @override
  Future<IosBackgroundModelTransferCompletion> start(
    IosBackgroundModelTransferRequest request,
  ) async {
    final payload = await _methodChannel.invokeMethod<Object?>(
      'download',
      request.toPlatformArguments(),
    );
    final map = _requireMap(payload, operation: 'download');
    return IosBackgroundModelTransferCompletion(
      transferId: _requireString(map, 'transferId'),
      receivedBytes: _requireNonNegativeInt(map, 'receivedBytes'),
    );
  }

  @override
  Future<void> cancel(String transferId) {
    return _methodChannel.invokeMethod<void>('cancel', {
      'transferId': transferId,
    });
  }
}

/// Downloads model artifacts through an iOS background URLSession.
///
/// URLSession owns partial bytes outside the model store's staging path. A
/// repeated call with the same request reattaches to that task and reports its
/// reconciled progress. Explicit cancellation waits for native cleanup before
/// returning a cancellation signal to the store.
final class IosBackgroundModelArtifactDownloader implements ModelArtifactDownloader {
  /// Creates the production downloader.
  IosBackgroundModelArtifactDownloader({
    IosBackgroundModelTransferBridge? bridge,
  }) : _bridge = bridge ?? MethodChannelIosBackgroundModelTransferBridge();

  final IosBackgroundModelTransferBridge _bridge;

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) async {
    final request = IosBackgroundModelTransferRequest(
      source: source,
      destinationPath: destinationPath,
      expectedBytes: expectedBytes,
    );
    cancellation.throwIfCancelled();

    var lastReportedBytes = -1;
    void reportProgress(int receivedBytes) {
      if (receivedBytes <= lastReportedBytes) return;
      lastReportedBytes = receivedBytes;
      onProgress(receivedBytes);
    }

    final progressSubscription = _bridge.progressEvents.where((event) => event.transferId == request.transferId).listen(
      (event) {
        if (!cancellation.isCancelled) reportProgress(event.receivedBytes);
      },
    );
    final startTask = _bridge.start(request);
    final cancellationTask = Completer<void>();
    final removeCancellationListener = cancellation.addListener(() {
      unawaited(
        _bridge
            .cancel(request.transferId)
            .then<void>(
              (_) {
                if (!cancellationTask.isCompleted) cancellationTask.complete();
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!cancellationTask.isCompleted) {
                  cancellationTask.completeError(error, stackTrace);
                }
              },
            ),
      );
    });

    try {
      final outcome = await Future.any<_TransferOutcome>([
        startTask.then(_TransferOutcome.completed),
        cancellationTask.future.then((_) => const _TransferOutcome.cancelled()),
      ]);
      if (outcome.cancelled || cancellation.isCancelled) {
        // The native cancellation future completes only after the task and its
        // persistent resume data have both been removed.
        throw const ModelDownloadCancelledException();
      }
      final completion = outcome.completion!;
      if (completion.transferId != request.transferId) {
        throw const FormatException(
          'Model download channel completed a different transfer.',
        );
      }
      if (completion.receivedBytes != expectedBytes) {
        throw ModelDownloadSizeException(
          expectedBytes: expectedBytes,
          actualBytes: completion.receivedBytes,
        );
      }
      reportProgress(completion.receivedBytes);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error, source, destinationPath);
    } finally {
      removeCancellationListener();
      await progressSubscription.cancel();
    }
  }
}

final class _TransferOutcome {
  const _TransferOutcome.completed(this.completion) : cancelled = false;

  const _TransferOutcome.cancelled() : completion = null, cancelled = true;

  final IosBackgroundModelTransferCompletion? completion;
  final bool cancelled;
}

String _transferIdFor({
  required Uri source,
  required String destinationPath,
  required int expectedBytes,
}) {
  final identity = '$source\n$destinationPath\n$expectedBytes';
  return sha256.convert(utf8.encode(identity)).toString();
}

IosBackgroundModelTransferProgress _parseProgress(Object? payload) {
  final map = _requireMap(payload, operation: 'progress');
  return IosBackgroundModelTransferProgress(
    transferId: _requireString(map, 'transferId'),
    receivedBytes: _requireNonNegativeInt(map, 'receivedBytes'),
    expectedBytes: _requirePositiveInt(map, 'expectedBytes'),
  );
}

Map<Object?, Object?> _requireMap(
  Object? payload, {
  required String operation,
}) {
  if (payload case final Map<Object?, Object?> map) return map;
  throw FormatException(
    'Model download $operation returned an invalid platform payload.',
  );
}

String _requireString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException(
    'Model download payload field "$key" must be a non-empty string.',
  );
}

int _requireNonNegativeInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int && value >= 0) return value;
  throw FormatException(
    'Model download payload field "$key" must be a non-negative integer.',
  );
}

int _requirePositiveInt(Map<Object?, Object?> map, String key) {
  final value = _requireNonNegativeInt(map, key);
  if (value > 0) return value;
  throw FormatException(
    'Model download payload field "$key" must be positive.',
  );
}

Exception _mapPlatformException(
  PlatformException error,
  Uri source,
  String destinationPath,
) {
  final details = error.details;
  final map = details is Map<Object?, Object?> ? details : null;
  return switch (error.code) {
    'MODEL_DOWNLOAD_CANCELLED' => const ModelDownloadCancelledException(),
    'MODEL_DOWNLOAD_HTTP_STATUS' => ModelHttpStatusException(
      _requireNonNegativeInt(map ?? const {}, 'statusCode'),
      source,
    ),
    'MODEL_DOWNLOAD_SIZE_MISMATCH' => ModelDownloadSizeException(
      expectedBytes: _requireNonNegativeInt(map ?? const {}, 'expectedBytes'),
      actualBytes: _requireNonNegativeInt(map ?? const {}, 'actualBytes'),
    ),
    'MODEL_DOWNLOAD_NETWORK' => SocketException(
      error.message ?? 'The background model transfer failed.',
    ),
    'MODEL_DOWNLOAD_IO' => FileSystemException(
      error.message ?? 'The background model transfer could not publish bytes.',
      destinationPath,
    ),
    _ => error,
  };
}
