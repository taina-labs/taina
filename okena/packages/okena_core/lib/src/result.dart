import 'package:okena_core/src/taina_error.dart';

/// The result of an operation that can fail with a [TainaError].
///
/// Expected failures are values, not exceptions: nothing throws across a
/// boundary the caller does not own.
typedef TainaResult<T> = Result<T>;

sealed class Result<T> {
  const Result();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(TainaError error) onFailure,
  }) {
    return switch (this) {
      Ok<T>(:final value) => onSuccess(value),
      Err<T>(:final error) => onFailure(error),
    };
  }

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => Ok<R>(transform(value)),
      Err<T>(:final error) => Err<R>(error),
    };
  }

  /// Sequences a step that can fail: the first failure short circuits the
  /// rest, like the Swift core's `then`.
  Future<Result<R>> then<R>(Future<Result<R>> Function(T value) next) async {
    return switch (this) {
      Ok<T>(:final value) => await next(value),
      Err<T>(:final error) => Err<R>(error),
    };
  }

  bool get isSuccess => this is Ok<T>;

  bool get isFailure => this is Err<T>;

  T? get value => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  TainaError? get error => switch (this) {
    Ok<T>() => null,
    Err<T>(:final error) => error,
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  @override
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);

  @override
  final TainaError error;
}
