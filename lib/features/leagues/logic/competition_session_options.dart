// lib/features/leagues/logic/competition_session_options.dart
//
// Pure helpers for the Competition Session picker. No I/O, no Firestore --
// just generates a sensible, perpetually-fresh set of session options from
// the current date, and validates/normalizes custom organizer input.
//
// `League.season` (lib/features/leagues/models/league.dart) is a plain
// String -- not a year, not an enum -- precisely so a competition can be
// "2026", "2026/2027", "Summer 2027", or any other organizer-chosen label.
// These helpers never decide what gets stored: they only (a) suggest a
// starting set of options for the picker UI, and (b) validate a custom
// value the organizer types in. The organizer's choice is always final.

class CompetitionSessionOptions {
  const CompetitionSessionOptions._();

  /// Mirrors firestore.rules' size cap on League.season, so a value that
  /// passes client-side validation is never silently rejected server-side.
  static const int maxLength = 60;

  /// Dynamically generates six likely session values anchored to [now]
  /// (defaults to the real current time) -- never a fixed year, so this
  /// keeps producing sensible options in 2027, 2028, 2029, ... without a
  /// code change. Three single calendar years (current, next, the one
  /// after) followed by three year-range sessions, matching how this
  /// product's own competitions are actually run (single-year tournaments
  /// and cross-year seasons both exist side by side).
  static List<String> generate({DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    return <String>[
      '$year',
      '${year + 1}',
      '${year + 2}',
      '$year/${year + 1}',
      '${year + 1}/${year + 2}',
      '${year + 2}/${year + 3}',
    ];
  }

  /// A single pre-filled suggestion for a brand-new competition --
  /// deliberately the current/next year range, since a league or
  /// tournament is more often a season spanning a year boundary than a
  /// single calendar year. This is ONLY a convenience default: the
  /// organizer sees it already selected but can change it to any other
  /// generated option or a fully custom value before creating the
  /// competition -- it is never forced.
  static String suggestedDefault({DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    return '$year/${year + 1}';
  }

  /// Validates and trims a custom session string the organizer typed in.
  /// Returns null if the value is empty (after trimming) or exceeds
  /// [maxLength] -- callers should show a validation error in that case,
  /// never silently fall back to a default.
  static String? normalizeCustom(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) return null;
    return trimmed;
  }
}
