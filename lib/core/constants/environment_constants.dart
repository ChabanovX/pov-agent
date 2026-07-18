/// Shared compile-time environment configuration.
library;

/// The observation source selected by `OBSERVATION_SOURCE` at build time.
const String kObservationSource = String.fromEnvironment(
  'OBSERVATION_SOURCE',
  defaultValue: 'camera',
);
