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

  static Uri? cloudinarySignHighlightUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/cloudinary/sign-highlight');
  }

  // ── Football Hub (API-Football, proxied + cached server-side) ──────────

  static Uri? footballFixturesUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/fixtures');
  }

  static Uri? footballStandingsUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/standings');
  }

  static Uri? footballLeaguesUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/leagues');
  }

  static Uri? footballTeamsUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/teams');
  }

  static Uri? footballSquadUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/squad');
  }

  static Uri? footballPlayerUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/player');
  }

  static Uri? footballFixtureEventsUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/fixture-events');
  }

  // GNews, proxied + cached server-side -- a different provider/quota
  // from API-Football above, same "key never ships to the app" reason.
  static Uri? footballNewsUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/football/news');
  }

  // ── Team claims (external/manually-created team -> real account) ───────

  static Uri? teamClaimGenerateUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/teams/claim/generate');
  }

  static Uri? teamClaimPreviewUrl(String token) {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/teams/claim/preview').replace(queryParameters: {'token': token});
  }

  static Uri? teamClaimConfirmUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/teams/claim/confirm');
  }

  static Uri? teamClaimRevokeUrl() {
    final base = _normalizedWorkerBase;
    if (base.isEmpty) return null;
    return Uri.parse('$base/teams/claim/revoke');
  }
}
