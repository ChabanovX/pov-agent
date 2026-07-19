import 'package:pov_agent/shared/domain/app_result.dart';

/// One active native text-generation operation.
abstract interface class GenerationHandle {
  /// Non-empty, user-visible answer fragments in generation order.
  ///
  /// Reasoning blocks and model control tokens must not cross this boundary.
  /// The stream closes normally and never emits errors; [completion] is the
  /// sole normalized terminal outcome.
  Stream<String> get chunks;

  /// Settles after token delivery ends and native generation has stopped.
  ///
  /// Normal completion returns the complete visible answer. Cancellation may
  /// return the visible prefix as success; the caller that requested cancel
  /// remains responsible for excluding that prefix from conversation history.
  Future<AppResult<String>> get completion;

  /// Cooperatively stops generation.
  ///
  /// Calls are idempotent. The returned future settles only after native work
  /// has stopped, so model memory can be unloaded safely afterwards.
  Future<void> cancel();
}
