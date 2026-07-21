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
}
