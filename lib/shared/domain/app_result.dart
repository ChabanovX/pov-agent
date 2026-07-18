import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

/// The success or normalized failure produced by an application operation.
sealed class AppResult<T> {
  /// Creates an application result.
  const AppResult();

  /// Reduces this result with the matching success or failure callback.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      AppSuccess<T>(:final value) => onSuccess(value),
      AppError<T>(:final failure) => onFailure(failure),
    };
  }

  /// Maps a successful value while preserving an existing failure.
  AppResult<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      AppSuccess<T>(:final value) => AppSuccess(transform(value)),
      AppError<T>(:final failure) => AppError(failure),
    };
  }
}

/// A successful application result containing [value].
final class AppSuccess<T> extends AppResult<T> {
  /// Creates a successful result containing [value].
  const AppSuccess(this.value);

  /// The operation value.
  final T value;
}

/// An unsuccessful application result containing a normalized [failure].
final class AppError<T> extends AppResult<T> {
  /// Creates an unsuccessful result containing [failure].
  const AppError(this.failure);

  /// The normalized operation failure.
  final AppFailure failure;
}

/// A single value used when an operation has no meaningful result payload.
final class Unit {
  const Unit._();

  /// The sole unit value.
  static const value = Unit._();
}
