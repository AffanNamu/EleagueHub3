// lib/features/leagues/data/competition_rules_firestore_paths.dart
//
// NEW FILE.
//
// Centralized Firestore path/collection constants for the Competition
// Rules feature, mirroring the pattern already used by
// MasterLeagueFirestorePaths.
//
// Structure:
//   leagues/{leagueId}/competitionRules/current   <- live/published rules
//   leagues/{leagueId}/competitionRules/v{n}      <- archived versions,
//                                                     only written once a
//                                                     version has been
//                                                     locked and then edited
class CompetitionRulesFirestorePaths {
  static const String leaguesCollection = 'leagues';
  static const String competitionRulesSubcollection = 'competitionRules';

  /// Doc id for the live/current rules document.
  static const String currentDocId = 'current';

  /// Doc id for an archived historical version.
  static String historyDocId(int version) => 'v$version';
}
