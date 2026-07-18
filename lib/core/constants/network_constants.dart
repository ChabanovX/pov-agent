/// Shared network configuration constants.
///
/// Keep endpoints, build-time network configuration, timeouts, and retry
/// policy here. Per-file implementation details should stay private next to
/// the code that uses them.
library;

/// The service base URL selected by `API_BASE_URL` at build time.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
);

/// The maximum wait for establishing a network connection.
const Duration kNetworkConnectTimeout = Duration(seconds: 10);

/// The maximum wait for receiving a network response.
const Duration kNetworkReceiveTimeout = Duration(seconds: 12);

/// The maximum wait for sending a network request.
const Duration kNetworkSendTimeout = Duration(seconds: 10);

/// The maximum number of retries after the initial request.
const int kNetworkMaxRetries = 1;

/// The exponential multiplier applied between retry delays.
const double kNetworkRetryMultiplier = 2;

/// The delay before the first network retry.
const Duration kNetworkRetryBaseDelay = Duration(seconds: 1);

/// The upper bound for a calculated network retry delay.
const Duration kNetworkRetryMaxDelay = Duration(seconds: 30);
