class BackendConfig {
  /// Base URL for your Firebase Functions HTTPS endpoints.
  ///
  /// Example:
  ///   https://europe-west2-YOUR_PROJECT.cloudfunctions.net
  ///
  /// Optional for now (Spark plan users can leave empty).
  static const String functionsBaseUrl = String.fromEnvironment('FUNCTIONS_BASE_URL', defaultValue: '');

  static bool get functionsEnabled => functionsBaseUrl.trim().isNotEmpty;

  static Uri? verifyFlutterwavePaymentUrl() {
    final base = functionsBaseUrl.trim();
    if (base.isEmpty) return null;

    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized/verifyFlutterwavePayment');
  }
}
