import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

// The mapper stays injectable so data adapters can normalize errors through a
// replaceable boundary contract.
/// A boundary that converts infrastructure errors into application failures.
// ignore: one_member_abstracts
abstract interface class FailureMapper {
  /// The normalized failure for [error] and its [stackTrace].
  AppFailure map(Object error, StackTrace stackTrace);
}

/// A fallback mapper for errors without a more specific category.
final class DefaultFailureMapper implements FailureMapper {
  /// Creates the default failure mapper.
  const DefaultFailureMapper();

  @override
  AppFailure map(Object error, StackTrace stackTrace) {
    return UnexpectedFailure(cause: error, stackTrace: stackTrace);
  }
}
