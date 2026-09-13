/// Supported games. Values are the exact strings stored in Firestore
/// under  doc IDs and .
/// Adding a new game = add a case here. No migration needed.
class GameId {
  static const localFootball = 'local_football';
  static const eFootball = 'efootball';
  static const eaFc = 'ea_fc';
  static const eaFcMobile = 'ea_fc_mobile';
  static const dreamLeagueSoccer = 'dream_league_soccer';
  static const totalFootball = 'total_football';

  static const List<String> all = [
    localFootball,
    eFootball,
    eaFc,
    eaFcMobile,
    dreamLeagueSoccer,
    totalFootball,
  ];

  static String label(String id) {
    switch (id) {
      case eFootball:
        return 'eFootball';
      case eaFc:
        return 'EA SPORTS FC';
      case eaFcMobile:
        return 'EA SPORTS FC Mobile';
      case dreamLeagueSoccer:
        return 'Dream League Soccer';
      case totalFootball:
        return 'Total Football';
      case localFootball:
      default:
        return 'Local Football';
    }
  }

  /// Maps one of the free-text game titles offered on the onboarding
  /// screen (see OnboardingScreen._gameGroups / web's GAME_GROUPS — kept
  /// identical on both platforms) to the 6-value GameId taxonomy used by
  /// squads and the team profile. Titles from the same publisher/series
  /// collapse onto one bucket (e.g. "FIFA 23" -> eaFc); titles with no
  /// specific bucket fall into totalFootball as the general "other
  /// football-adjacent game" catch-all.
  static String fromOnboardingLabel(String label) {
    switch (label.trim()) {
      case 'EA Sports FC 25':
      case 'FIFA 23':
        return eaFc;
      case 'eFootball':
      case 'PES 2021':
      case 'PES 2017':
        return eFootball;
      case 'EA Sports FC Mobile':
        return eaFcMobile;
      case 'Dream League Soccer':
        return dreamLeagueSoccer;
      case 'Total Football':
      case 'Soccer Stars':
      case 'Football Strike':
      case 'Mini Football':
      case 'Score! Match':
      case 'UFL':
      case 'Rocket League':
        return totalFootball;
      default:
        return localFootball;
    }
  }
}
