/// The session-only cadence used by the automatic observer.
enum ObserverInterval {
  /// Generates an observation every ten seconds.
  tenSeconds(10),

  /// Generates an observation every thirty seconds.
  thirtySeconds(30),

  /// Generates an observation every minute.
  oneMinute(60),

  /// Generates an observation every two minutes.
  twoMinutes(120),

  /// Generates an observation every five minutes.
  fiveMinutes(300);

  const ObserverInterval(this.seconds);

  /// The interval length in seconds.
  final int seconds;

  /// The interval as a timer duration.
  Duration get duration => Duration(seconds: seconds);
}
