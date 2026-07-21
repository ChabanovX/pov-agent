import 'dart:async';

import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';

/// Creates one owned periodic timer for automatic-observation ticks.
typedef ObserverPeriodicTimerFactory =
    Timer Function(
      Duration interval,
      void Function() onTick,
    );

/// Encapsulates the timer slot owned by the process-level observer Bloc.
///
/// This controller does not decide whether observation is allowed. Its owner
/// applies foreground and generation policy before replacing or stopping the
/// timer, while this object guarantees that only one periodic source exists.
final class ObserverTimerController {
  /// Creates an idle timer slot that forwards accepted wall-clock ticks.
  factory ObserverTimerController({
    required void Function() onTick,
    ObserverPeriodicTimerFactory periodicTimerFactory = _createPeriodicTimer,
  }) {
    return ObserverTimerController._(onTick, periodicTimerFactory);
  }

  ObserverTimerController._(this._onTick, this._periodicTimerFactory);

  final void Function() _onTick;
  final ObserverPeriodicTimerFactory _periodicTimerFactory;
  Timer? _timer;
  var _closed = false;

  /// Replaces any existing timer with [interval].
  void replace(ObserverInterval interval) {
    if (_closed) return;
    stop();
    _timer = _periodicTimerFactory(interval.duration, _onTick);
  }

  /// Cancels the current periodic source, if any.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Permanently releases the currently owned timer.
  void close() {
    if (_closed) return;
    stop();
    _closed = true;
  }
}

Timer _createPeriodicTimer(Duration interval, void Function() onTick) {
  return Timer.periodic(interval, (_) => onTick());
}
