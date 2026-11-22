// lib/core/moderation/objectionable_content_filter.dart
//
// App Review Guideline 1.2 requires apps with user-generated content to
// include "a method for filtering objectionable material from being posted
// to the app", alongside reporting and blocking (already implemented in
// lib/features/moderation). This is that filter: a word-boundary blocklist
// applied before any post, comment, chat message or discussion is written.
//
// It is deliberately conservative to avoid false positives on ordinary
// sports talk ("kill the game", "shoot", "classic", "Scunthorpe"): matching
// is per word, after normalising case, common character substitutions
// (sh1t, b!tch), spaced-out letters (f u c k) and stretched letters
// (fuuuck). Report/block plus the
// admin review queue remain the backstop for anything it misses; this is
// client-side and best-effort, like the existing QuickMessagePolicy.

class ObjectionableContentException implements Exception {
  const ObjectionableContentException([
    this.message =
        "This contains language that isn't allowed on eSportlyic. Please edit it and try again.",
  ]);
  final String message;
  @override
  String toString() => message;
}

class ObjectionableContentFilter {
  const ObjectionableContentFilter._();

  // Whole words that are blocked. Stored already normalised (lowercase,
  // repeated letters collapsed: "asshole" -> "ashole"), because input goes
  // through the same normalisation before comparison. Words that collide
  // with ordinary football vocabulary or names once normalised are left
  // out on purpose: "niger" (the country), "dick" (a common first name),
  // "chink" ("chink in the armour"), "coon" (collapses to "con").
  static const Set<String> _blockedWords = <String>{
    // profanity / sexual insults
    'fuck', 'fucker', 'fuckers', 'fucking', 'fuckin', 'motherfucker',
    'motherfuckers', 'shit', 'shits', 'shity', 'bulshit', 'bitch',
    'bitches', 'ashole', 'asholes', 'bastard', 'bastards', 'cunt', 'cunts',
    'dickhead', 'dickheads', 'pusy', 'twat', 'wanker', 'whore', 'whores',
    'slut', 'sluts', 'cock', 'cocks', 'cocksucker', 'blowjob', 'dildo',
    'porn', 'porno', 'pornography', 'nudes', 'rape', 'rapist', 'molest',
    // slurs
    'niga', 'nigas', 'nigah', 'fagot', 'fagots', 'fag', 'fags', 'dyke',
    'dykes', 'retard', 'retards', 'retarded', 'trany', 'spic', 'spics',
    'kike', 'kikes', 'wetback', 'wetbacks', 'paki',
    // threats / self-harm incitement
    'kys',
  };

  // Checked on the letters-only spelling (substitutions applied, repeats NOT
  // collapsed), for slurs whose collapsed form is an innocent word.
  static const Set<String> _blockedExactSpellings = <String>{
    'nigger', 'niggers', 'nigga', 'niggas',
  };

  // Multi-word phrases, matched on word boundaries in the normalised text
  // so that e.g. "skill yourself" is not caught by "kill yourself".
  static final List<RegExp> _blockedPhrases = <RegExp>[
    RegExp(r'\bkil ?(?:your|ur|yo) ?self\b'),
  ];

  static const Map<String, String> _substitutions = <String, String>{
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
    '@': 'a', r'$': 's', '!': 'i', '|': 'i', '€': 'e', '¡': 'i',
  };

  static final RegExp _nonLetter = RegExp(r'[^a-z]+');
  static final RegExp _repeats = RegExp(r'([a-z])\1+');
  // Single characters separated by spaces/dots ("f u c k", "k.y.s").
  static final RegExp _spacedLetters = RegExp(r'\b(?:[a-z][\s._-]){2,}[a-z]\b');

  // Lowercase, undo character substitutions, and join letters written with
  // separators ("f u c k"). Repeated letters are NOT collapsed here.
  static String _substituted(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_substitutions[ch] ?? ch);
    }
    return buffer.toString().replaceAllMapped(
          _spacedLetters,
          (m) => m.group(0)!.replaceAll(RegExp(r'[\s._-]'), ''),
        );
  }

  static String _collapseRepeats(String s) =>
      s.replaceAllMapped(_repeats, (m) => m.group(1)!);

  /// Returns the first blocked term found in [text], or null if it is clean.
  static String? findViolation(String text) {
    if (text.trim().isEmpty) return null;
    final substituted = _substituted(text);

    for (final word in substituted.split(_nonLetter)) {
      if (word.isEmpty) continue;
      if (_blockedExactSpellings.contains(word)) return word;
      final collapsed = _collapseRepeats(word);
      if (_blockedWords.contains(collapsed)) return collapsed;
    }

    final spaced =
        _collapseRepeats(substituted.replaceAll(_nonLetter, ' ')).trim();
    for (final phrase in _blockedPhrases) {
      final m = phrase.firstMatch(spaced);
      if (m != null) return m.group(0);
    }
    return null;
  }

  static bool isAllowed(String text) => findViolation(text) == null;

  /// Throws [ObjectionableContentException] when [text] contains a blocked
  /// term. Repositories call this before writing any user-generated text.
  static void ensureAllowed(String text) {
    if (findViolation(text) != null) {
      throw const ObjectionableContentException();
    }
  }
}
