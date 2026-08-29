///core/config/BackendConfig
class BackendConfig {
  static const String functionsBaseUrl =
      String.fromEnvironment('FUNCTIONS_BASE_URL', defaultValue: '');

  static const String workerBaseUrl =
      String.fromEnvironment('EH_WORKER_BASE_URL', defaultValue: '');

  static bool get functionsEnabled => functionsBaseUrl.trim().isNotEmpty;

  static bool get workerEnabled => workerBaseUrl.trim().isNotEmpty;

  static String get _normalizedFunctionsBase {
    final base = functionsBaseUrl.trim();
    if (base.isEmpty) return '';
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static String get _normalizedWorkerBase {
    final base = workerBaseUrl.trim();
    if (base.isEmpty) return '';
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static Uri? verifyFlutterwavePaymentUrl() {
    final base = _normalizedFunctionsBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/verifyFlutterwavePayment');
  }

  static Uri? workerFlutterwaveVerifyUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/flutterwave/verify');
  }

  static Uri? premiumActivateUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/premium/activate');
  }

  static Uri? organizerProActivateUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/organizer-pro/activate');
  }
}
