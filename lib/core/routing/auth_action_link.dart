enum AuthEmailActionMode { verifyEmail, resetPassword }

class AuthEmailActionLink {
  final AuthEmailActionMode mode;
  final String oobCode;

  const AuthEmailActionLink({
    required this.mode,
    required this.oobCode,
  });

  static AuthEmailActionLink? tryParse(Uri uri) {
    // Supports:
    // - Custom scheme: eleaguehub://auth?mode=resetPassword&oobCode=...
    // - HTTPS links if you later add Android App Links / iOS Universal Links.
    final qp = uri.queryParameters;
    final modeStr = (qp['mode'] ?? '').trim();
    final oobCode = (qp['oobCode'] ?? '').trim();
    if (modeStr.isEmpty || oobCode.isEmpty) return null;

    switch (modeStr) {
      case 'verifyEmail':
        return AuthEmailActionLink(mode: AuthEmailActionMode.verifyEmail, oobCode: oobCode);
      case 'resetPassword':
        return AuthEmailActionLink(mode: AuthEmailActionMode.resetPassword, oobCode: oobCode);
      default:
        return null;
    }
  }
}
