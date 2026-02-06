/// Summary:
/// - Client-side validation for Premium custom quick messages.
/// - Best-effort anti-abuse (cannot guarantee against modified clients).
class QuickMessagePolicy {
  // Your rules (from user):
  static const int maxCustomCount = 15;
  static const int maxChars = 15;
  static const bool allowEmojis = true;
  static const bool allowUrlsAndMentions = false;

  // Safe defaults fallback (English).
  static const List<String> defaultFallback = <String>[
    'Focus!',
    'Calm down',
    'We got this',
    'One more goal!',
    'Don’t give up',
    'Sorry',
    'Unlucky',
    'What a goal!',
    'Ref??',
  ];

  // Best-effort profanity/abuse blocklist (English-centric).
  // Keep this list minimal to reduce false-positives; expand as needed.
  static const List<String> _blockedTokens = <String>[
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'bastard',
    'dick',
    'pussy',
    'cunt',
  ];

  static final RegExp _urlLike = RegExp(r'(https?:\/\/|www\.|\.com\b|\.net\b|\.org\b)', caseSensitive: false);
  static final RegExp _mentionLike = RegExp(r'@[\w_]+', caseSensitive: false);

  // Loose "phone-number like" pattern (optional).
  static final RegExp _phoneLike = RegExp(r'(\+?\d[\d\-\s]{6,}\d)');

  static String normalize(String raw) {
    // Trim and collapse repeated whitespace.
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  static QuickMessageValidationResult validateCustomMessage(String raw) {
    final s = normalize(raw);
    if (s.isEmpty) return const QuickMessageValidationResult.invalid('Message is empty');
    if (s.runes.length > maxChars) return QuickMessageValidationResult.invalid('Max $maxChars characters');

    if (!allowUrlsAndMentions) {
      if (_urlLike.hasMatch(s)) return const QuickMessageValidationResult.invalid('Links are not allowed');
      if (_mentionLike.hasMatch(s)) return const QuickMessageValidationResult.invalid('Mentions are not allowed');
      if (_phoneLike.hasMatch(s)) return const QuickMessageValidationResult.invalid('Phone numbers are not allowed');
    }

    final lower = s.toLowerCase();
    for (final t in _blockedTokens) {
      if (lower.contains(t)) {
        return const QuickMessageValidationResult.invalid('Message is not allowed');
      }
    }

    // If emojis not allowed, restrict to basic punctuation/letters/numbers/spaces.
    if (!allowEmojis) {
      final ok = RegExp(r"^[a-zA-Z0-9\s\.\,\!\?\-\’\'\"]+$").hasMatch(s);
      if (!ok) return const QuickMessageValidationResult.invalid('Only plain text is allowed');
    }

    return QuickMessageValidationResult.valid(s);
  }

  static List<String> sanitizeList(List<String> raw) {
    // Apply normalize + remove empty + trim to max count.
    final cleaned = <String>[];
    for (final m in raw) {
      final v = normalize(m);
      if (v.isEmpty) continue;
      cleaned.add(v);
      if (cleaned.length >= maxCustomCount) break;
    }
    return cleaned;
  }
}

class QuickMessageValidationResult {
  final bool ok;
  final String value;
  final String error;

  const QuickMessageValidationResult._(this.ok, this.value, this.error);

  const QuickMessageValidationResult.valid(String value) : this._(true, value, '');
  const QuickMessageValidationResult.invalid(String error) : this._(false, '', error);
}
