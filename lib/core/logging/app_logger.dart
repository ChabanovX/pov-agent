import 'package:logger/logger.dart';

final class AppLogger {
  AppLogger(this.tag);

  static final Logger _logger = Logger();

  final String tag;

  void d(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(_format(message), error: error, stackTrace: stackTrace);
  }

  void i(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(_format(message), error: error, stackTrace: stackTrace);
  }

  void w(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(_format(message), error: error, stackTrace: stackTrace);
  }

  void e(Object? message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(_format(message), error: error, stackTrace: stackTrace);
  }

  String _format(Object? message) => '[$tag] $message';
}
