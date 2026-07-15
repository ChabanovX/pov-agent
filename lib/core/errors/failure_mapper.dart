import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

// The mapper stays injectable so data adapters can normalize errors through a
// replaceable boundary contract.
// ignore: one_member_abstracts
abstract interface class FailureMapper {
  AppFailure map(Object error, StackTrace stackTrace);
}

final class DefaultFailureMapper implements FailureMapper {
  const DefaultFailureMapper();

  @override
  AppFailure map(Object error, StackTrace stackTrace) {
    return UnexpectedFailure(cause: error, stackTrace: stackTrace);
  }
}
