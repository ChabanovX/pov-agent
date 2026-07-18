import 'package:logger/logger.dart';

/// A tagged facade over the application's logging backend.
final class AppLogger {
  /// Creates a logger whose messages are prefixed with [tag].
  AppLogger(this.tag);

  static final Logger _logger = Logger();

  /// The component tag prepended to each message.
  final String tag;

  /// Logs a debug [message] with optional error diagnostics.
  void d(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(_format(message), error: error, stackTrace: stackTrace);
  }

  /// Logs an informational [message] with optional error diagnostics.
  void i(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(_format(message), error: error, stackTrace: stackTrace);
  }

  /// Logs a warning [message] with optional error diagnostics.
  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(_format(message), error: error, stackTrace: stackTrace);
  }

  /// Logs an error [message] with optional error diagnostics.
  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(_format(message), error: error, stackTrace: stackTrace);
  }

  String _format(Object? message) => '[$tag] $message';
}
