/// Shared compile-time environment configuration.
library;

const String kObservationSource = String.fromEnvironment(
  'OBSERVATION_SOURCE',
  defaultValue: 'camera',
);
