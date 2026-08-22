//AuthValidators
class AuthValidators {
  static final RegExp _emailRe = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  );

  static bool isValidEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    if (e.length > 254) return false;
    return _emailRe.hasMatch(e);
  }

  static String? validateEmail(String email) {
    if (!isValidEmail(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? validatePassword(String password, {int minLength = 6}) {
    if (password.isEmpty) return 'Password is required.';
    if (password.length < minLength) return 'Password must be at least $minLength characters.';
    return null;
  }

  static String? validateActionCodeOrLink(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return 'Enter the code (or paste the full link) from your email.';
    if (raw.length < 6) return 'That code looks too short.';
    if (raw.length > 2048) return 'That value is too long.';
    return null;
  }

  /// Extracts Firebase Auth action code (oobCode) from:
  /// - a pasted full URL (…?oobCode=XYZ…)
  /// - or returns the trimmed input as-is.
  static String extractOobCode(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;

    try {
      final uri = Uri.parse(raw);
      final code = uri.queryParameters['oobCode'];
      if (code != null && code.trim().isNotEmpty) return code.trim();
    } catch (_) {
      // Not a URL; treat as code.
    }

    if (raw.contains('oobCode=')) {
      try {
        final uri = Uri.parse('https://local/?$raw');
        final code = uri.queryParameters['oobCode'];
        if (code != null && code.trim().isNotEmpty) return code.trim();
      } catch (_) {
        // fall through
      }
    }

    return raw;
  }
}
