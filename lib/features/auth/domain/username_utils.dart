// lib/features/auth/domain/username_utils.dart

/// Single source of truth for username normalization, validation, and
/// reserved-word checks.
///
/// Used by BOTH automatic username generation (from display name) and
/// manual username editing in [UserProfileRepository], so behavior is
/// guaranteed consistent everywhere in the app. Do not duplicate this
/// logic anywhere else.
class UsernameUtils {
  UsernameUtils._();

  static const int minLength = 3;
  static const int maxLength = 20;

  /// Usernames that must never be assignable by a regular user, either
  /// automatically or manually. Comparisons are always against the
  /// lowercase canonical form. Kept intentionally small and generic —
  /// extend as needed.
  static const Set<String> _reserved = <String>{
    'admin',
    'administrator',
    'root',
    'support',
    'help',
    'staff',
    'moderator',
    'mod',
    'esportlyic',
    'official',
    'system',
    'null',
    'undefined',
    'me',
    'you',
    'user',
    'anonymous',
    'superadmin',
    'owner',
    'team',
    'organizer',
    'organiser',
    'esportlyicteam',
  };

  /// Strict format check: lowercase letters, numbers, and underscore
  /// only, [minLength]-[maxLength] characters. Does NOT check
  /// availability or reserved status — see [isReserved].
  static bool isValidFormat(String candidate) {
    final value = candidate.trim();
    if (value.length < minLength || value.length > maxLength) {
      return false;
    }
    return RegExp(r'^[a-z0-9_]+$').hasMatch(value);
  }

  /// Reserved-word check. Expects (but does not require) a lowercase
  /// input — normalizes internally either way.
  static bool isReserved(String candidate) {
    return _reserved.contains(candidate.trim().toLowerCase());
  }

  /// Combines format + reserved checks into one call for convenience.
  /// This is the check that should gate any save/reservation attempt.
  static bool isValidUsername(String candidate) {
    final lower = candidate.trim().toLowerCase();
    return isValidFormat(lower) && !isReserved(lower);
  }

  /// Converts a display name into a normalized username candidate.
  ///
  /// Removes anything that is not a-z/0-9 (this naturally strips
  /// spaces, punctuation, symbols, and emoji, since none of those
  /// match `[a-z0-9]`), lowercases, and truncates to [maxLength].
  ///
  /// Examples:
  ///   "Mohammed Abubakar" -> "mohammedabubakar"
  ///   "Core Bridge"       -> "corebridge"
  ///   "John Doe!"         -> "johndoe"
  ///   "John   Doe"        -> "johndoe"
  ///
  /// Returns an empty string if nothing usable remains — callers must
  /// handle that case (e.g. fall back to a generic base like "user").
  static String normalizeToBaseUsername(String displayName) {
    var value = displayName.trim().toLowerCase();
    value = value.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value.length > maxLength) {
      value = value.substring(0, maxLength);
    }
    return value;
  }

  /// Pads a too-short base candidate up to [minLength] using a stable
  /// filler so it passes [isValidFormat]. Only used as a last resort
  /// during automatic generation, when the display name normalizes to
  /// fewer than [minLength] characters.
  static String padToMinLength(String base) {
    if (base.length >= minLength) return base;
    const filler = 'user';
    final needed = minLength - base.length;
    return '$base${filler.substring(0, needed.clamp(0, filler.length))}'
        .padRight(minLength, '0');
  }

  /// Presentation helper: the canonical stored value has no leading
  /// '@'; this adds it back for display only. Never store the result
  /// of this function.
  static String toDisplay(String storedUsernameLower) {
    final value = storedUsernameLower.trim();
    if (value.isEmpty) return '';
    return '@$value';
  }
}
