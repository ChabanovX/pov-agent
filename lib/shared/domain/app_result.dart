import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

sealed class AppResult<T> {
  const AppResult();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      AppSuccess<T>(:final value) => onSuccess(value),
      AppError<T>(:final failure) => onFailure(failure),
    };
  }

  AppResult<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      AppSuccess<T>(:final value) => AppSuccess(transform(value)),
      AppError<T>(:final failure) => AppError(failure),
    };
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.value);

  final T value;
}

final class AppError<T> extends AppResult<T> {
  const AppError(this.failure);

  final AppFailure failure;
}

final class Unit {
  const Unit._();

  static const value = Unit._();
}
