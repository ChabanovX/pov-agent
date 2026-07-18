// Reporting is a replaceable domain contract; production and no-op adapters
// must remain interchangeable at the composition boundary.
/// An error-reporting boundary that does not expose a logging backend.
// ignore: one_member_abstracts
abstract interface class IErrorReporter {
  /// Reports [error] with its [stackTrace] and optional diagnostic [context].
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  });
}

/// An error reporter that intentionally discards every report.
final class NoopErrorReporter implements IErrorReporter {
  /// Creates a no-op error reporter.
  const NoopErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {}
}
