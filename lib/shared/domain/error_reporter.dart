// Reporting is a replaceable domain contract; production and no-op adapters
// must remain interchangeable at the composition boundary.
// ignore: one_member_abstracts
abstract interface class IErrorReporter {
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  });
}

final class NoopErrorReporter implements IErrorReporter {
  const NoopErrorReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {}
}
