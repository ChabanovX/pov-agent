/// Shared network configuration constants.
///
/// Keep endpoints, build-time network configuration, timeouts, and retry
/// policy here. Per-file implementation details should stay private next to
/// the code that uses them.
library;

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
);

const Duration kNetworkConnectTimeout = Duration(seconds: 10);
const Duration kNetworkReceiveTimeout = Duration(seconds: 12);
const Duration kNetworkSendTimeout = Duration(seconds: 10);

const int kNetworkMaxRetries = 1;
const double kNetworkRetryMultiplier = 2;
const Duration kNetworkRetryBaseDelay = Duration(seconds: 1);
const Duration kNetworkRetryMaxDelay = Duration(seconds: 30);
