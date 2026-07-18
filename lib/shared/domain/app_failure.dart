/// A normalized application failure that is safe to cross layer boundaries.
sealed class AppFailure {
  /// Creates a failure with a stable [code] and optional diagnostic context.
  const AppFailure({
    required this.code,
    this.message,
    this.cause,
    this.stackTrace,
  });

  /// The stable machine-readable failure identifier.
  final String code;

  /// The optional diagnostic message, which is not presentation copy.
  final String? message;

  /// The optional underlying error retained for diagnostics.
  final Object? cause;

  /// The stack trace associated with [cause].
  final StackTrace? stackTrace;
}

/// A failure caused by unavailable network transport.
final class NetworkFailure extends AppFailure {
  /// Creates a network failure.
  const NetworkFailure({
    super.code = 'network',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure caused by missing or expired authorization.
final class UnauthorizedFailure extends AppFailure {
  /// Creates an authorization failure.
  const UnauthorizedFailure({
    super.code = 'unauthorized',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure caused by invalid input or invalid persisted data.
final class ValidationFailure extends AppFailure {
  /// Creates a validation failure with optional field-level [fields].
  const ValidationFailure({
    super.code = 'validation',
    super.message,
    this.fields = const {},
    super.cause,
    super.stackTrace,
  });

  /// Validation messages grouped by field name.
  final Map<String, List<String>> fields;
}

/// A failure caused by a missing resource.
final class NotFoundFailure extends AppFailure {
  /// Creates a not-found failure.
  const NotFoundFailure({
    super.code = 'not_found',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure reported by a remote service.
final class ServerFailure extends AppFailure {
  /// Creates a server failure.
  const ServerFailure({
    super.code = 'server',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure caused by local cache access or invalid cached data.
final class CacheFailure extends AppFailure {
  /// Creates a cache failure.
  const CacheFailure({
    super.code = 'cache',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure caused by a denied platform permission.
final class PermissionDeniedFailure extends AppFailure {
  /// Creates a permission failure.
  const PermissionDeniedFailure({
    super.code = 'permission_denied',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure caused by unavailable device hardware or native services.
final class DeviceUnavailableFailure extends AppFailure {
  /// Creates a device-unavailable failure.
  const DeviceUnavailableFailure({
    super.code = 'device_unavailable',
    super.message,
    super.cause,
    super.stackTrace,
  });
}

/// A failure that does not fit a more specific application category.
final class UnexpectedFailure extends AppFailure {
  /// Creates an unexpected failure.
  const UnexpectedFailure({
    super.code = 'unexpected',
    super.message,
    super.cause,
    super.stackTrace,
  });
}
