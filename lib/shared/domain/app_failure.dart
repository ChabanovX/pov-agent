sealed class AppFailure {
  const AppFailure({
    required this.code,
    this.message,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String? message;
  final Object? cause;
  final StackTrace? stackTrace;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.code = 'network',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure({
    super.code = 'unauthorized',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    super.code = 'validation',
    super.message,
    this.fields = const {},
    super.cause,
    super.stackTrace,
  });

  final Map<String, List<String>> fields;
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({
    super.code = 'not_found',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class ServerFailure extends AppFailure {
  const ServerFailure({
    super.code = 'server',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class CacheFailure extends AppFailure {
  const CacheFailure({
    super.code = 'cache',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class PermissionDeniedFailure extends AppFailure {
  const PermissionDeniedFailure({
    super.code = 'permission_denied',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class DeviceUnavailableFailure extends AppFailure {
  const DeviceUnavailableFailure({
    super.code = 'device_unavailable',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({
    super.code = 'unexpected',
    super.message,
    super.cause,
    super.stackTrace,
  });
}
