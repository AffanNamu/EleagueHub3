// lib/features/leagues/models/enums.dart
//
// NO CHANGES to existing values.
// Added WorldCupQualificationSlot for use by the World Cup engine.
// This does not affect any existing code paths.

enum LeaguePrivacy { public, private }

enum MatchStatus {
  scheduled,
  pendingProof,
  underReview,
  played,
  // Backward-compatible alias (if old code uses "completed")
  completed,
}

extension MatchStatusX on MatchStatus {
  static MatchStatus fromInt(int v) {
    if (v < 0 || v >= MatchStatus.values.length) {
      return MatchStatus.scheduled;
    }
    return MatchStatus.values[v];
  }

  /// Whether this status represents a finished match with a result.
  bool get isFinished =>
      this == MatchStatus.played || this == MatchStatus.completed;
}

/// Describes how a team qualified from the World Cup group stage.
///
/// Used internally by the World Cup engine to determine seeding
/// for the Round of 32 / Round of 16 bracket.
///
/// - [groupWinner]  → finished 1st in their group
/// - [groupRunnerUp] → finished 2nd in their group
/// - [bestThird]    → one of the 8 best 3rd-placed teams (FIFA 2026 only)
enum WorldCupQualificationSlot {
  groupWinner,
  groupRunnerUp,
  bestThird, // FIFA 2026 format only
}