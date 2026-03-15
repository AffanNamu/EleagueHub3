class BackendConfig {
  /// Base URL for your Firebase Functions HTTPS endpoints.
  ///
  /// Example:
  ///   https://europe-west2-YOUR_PROJECT.cloudfunctions.net
  ///
  /// Optional for now (Spark plan users can leave empty).
  static const String functionsBaseUrl =
      String.fromEnvironment('FUNCTIONS_BASE_URL', defaultValue: '');

  /// Base URL for your Cloudflare Worker.
  ///
  /// Example:
  ///   https://livekit-token-worker.YOUR_SUBDOMAIN.workers.dev
  ///
  /// This is the primary backend for payment verification on Spark plan.
  static const String workerBaseUrl =
      String.fromEnvironment('EH_WORKER_BASE_URL', defaultValue: '');

  static bool get functionsEnabled => functionsBaseUrl.trim().isNotEmpty;

  static bool get workerEnabled => workerBaseUrl.trim().isNotEmpty;

  static String get _normalizedWorkerBase {
    final base = workerBaseUrl.trim();
    if (base.isEmpty) return '';
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static Uri? verifyFlutterwavePaymentUrl() {
    final base = functionsBaseUrl.trim();
    if (base.isEmpty) return null;

    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized/verifyFlutterwavePayment');
  }

  /// Returns the URL for the premium activation endpoint on the Cloudflare Worker.
  /// Returns null if the worker is not configured.
  static Uri? premiumActivateUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/premium/activate');
  }

  /// Returns the URL for the organizer pro activation endpoint on the Cloudflare Worker.
  /// Returns null if the worker is not configured.
  static Uri? organizerProActivateUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/organizer-pro/activate');
  }
}
