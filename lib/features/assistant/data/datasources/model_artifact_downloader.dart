import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

/// Reports the cumulative number of downloaded bytes.
typedef ModelDownloadProgress = void Function(int receivedBytes);

/// Creates one HTTP client for an artifact transfer.
@visibleForTesting
typedef ModelHttpClientFactory = HttpClient Function();

/// Cooperative cancellation shared by the model store and downloader.
final class ModelDownloadCancellation {
  final List<void Function()> _listeners = [];
  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Cancels the transfer and synchronously notifies registered resources.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Throws when cancellation has already been requested.
  void throwIfCancelled() {
    if (_isCancelled) throw const ModelDownloadCancelledException();
  }

  /// Registers a synchronous callback and returns a removal function.
  void Function() addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Downloads one complete model artifact into a caller-owned staging path.
// Transport remains an injectable resource despite its deliberately narrow API.
// ignore: one_member_abstracts
abstract interface class ModelArtifactDownloader {
  /// Replaces [destinationPath] with bytes from [source].
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  });
}

/// Streams an HTTP model response directly into the staging file.
final class HttpModelArtifactDownloader implements ModelArtifactDownloader {
  /// Creates the production downloader.
  HttpModelArtifactDownloader({
    @visibleForTesting ModelHttpClientFactory? clientFactory,
    this.connectionTimeout = const Duration(seconds: 30),
    this.responseTimeout = const Duration(seconds: 30),
    this.bodyIdleTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final ModelHttpClientFactory _clientFactory;

  /// Maximum time allowed while establishing the HTTP connection.
  final Duration connectionTimeout;

  /// Maximum time allowed before the model host returns response headers.
  final Duration responseTimeout;

  /// Maximum silence allowed between response-body chunks.
  final Duration bodyIdleTimeout;

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) async {
    final client = _clientFactory()..connectionTimeout = connectionTimeout;
    HttpClientRequest? request;
    final removeCancellationListener = cancellation.addListener(() {
      request?.abort();
      client.close(force: true);
    });
    RandomAccessFile? output;

    try {
      cancellation.throwIfCancelled();
      request = await client.getUrl(source);
      cancellation.throwIfCancelled();
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      request.headers.set(HttpHeaders.userAgentHeader, 'pov-agent-model-store/1');
      final response = await request.close().timeout(
        responseTimeout,
        onTimeout: () {
          request?.abort();
          throw TimeoutException(
            'Model host did not return response headers within $responseTimeout.',
          );
        },
      );
      cancellation.throwIfCancelled();

      if (response.statusCode != HttpStatus.ok) {
        throw ModelHttpStatusException(response.statusCode, source);
      }
      if (response.contentLength >= 0 && response.contentLength != expectedBytes) {
        throw ModelDownloadSizeException(
          expectedBytes: expectedBytes,
          actualBytes: response.contentLength,
        );
      }

      output = await File(destinationPath).open(mode: FileMode.write);
      var receivedBytes = 0;
      final body = response.timeout(
        bodyIdleTimeout,
        onTimeout: (sink) {
          sink
            ..addError(
              TimeoutException(
                'Model host sent no bytes for $bodyIdleTimeout.',
              ),
            )
            ..close();
        },
      );
      await for (final chunk in body) {
        cancellation.throwIfCancelled();
        receivedBytes += chunk.length;
        if (receivedBytes > expectedBytes) {
          throw ModelDownloadSizeException(
            expectedBytes: expectedBytes,
            actualBytes: receivedBytes,
          );
        }
        // Awaiting each write pauses the HTTP subscription and bounds memory
        // even when the network is faster than the filesystem.
        await output.writeFrom(chunk);
        onProgress(receivedBytes);
      }
      cancellation.throwIfCancelled();
      await output.flush();
      if (receivedBytes != expectedBytes) {
        throw ModelDownloadSizeException(
          expectedBytes: expectedBytes,
          actualBytes: receivedBytes,
        );
      }
    } catch (error) {
      if (cancellation.isCancelled) {
        throw const ModelDownloadCancelledException();
      }
      rethrow;
    } finally {
      removeCancellationListener();
      client.close(force: true);
      await output?.close();
    }
  }
}

/// Signals that the owner cancelled a model download.
final class ModelDownloadCancelledException implements Exception {
  /// Creates the cancellation signal.
  const ModelDownloadCancelledException();

  @override
  String toString() => 'Model download was cancelled.';
}

/// Reports a non-success HTTP status from the model host.
final class ModelHttpStatusException implements Exception {
  /// Creates an HTTP status failure for [uri].
  const ModelHttpStatusException(this.statusCode, this.uri);

  /// The response status code.
  final int statusCode;

  /// The immutable artifact URL that returned the status.
  final Uri uri;

  @override
  String toString() => 'Model host returned HTTP $statusCode for $uri.';
}

/// Reports a transfer whose byte count differs from the pinned manifest.
final class ModelDownloadSizeException implements Exception {
  /// Creates a byte-count mismatch.
  const ModelDownloadSizeException({
    required this.expectedBytes,
    required this.actualBytes,
  });

  /// Pinned manifest byte count.
  final int expectedBytes;

  /// Observed response or transfer byte count.
  final int actualBytes;

  @override
  String toString() {
    return 'Model download contained $actualBytes bytes; expected $expectedBytes.';
  }
}
