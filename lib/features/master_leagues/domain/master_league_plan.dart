/// Tiered plan for Organizer Pro Mode.
///
/// Basic  - 1 master league, 3 competitions inside
/// Pro    - 5 master leagues, 9 competitions inside each
/// Elite  - unlimited master leagues and unlimited competitions
enum MasterLeaguePlan {
  basic(
    id: 'basic',
    displayName: 'Basic',
    description: '1 master league, up to 3 competitions',
    maxMasterLeagues: 1,
    maxLeagues: 3,
    maxTeamsPerLeague: 999,
    isPopular: false,
    unlimitedMasterLeagues: false,
    unlimitedCompetitions: false,
  ),
  pro(
    id: 'pro',
    displayName: 'Pro',
    description: '5 master leagues, up to 9 competitions each',
    maxMasterLeagues: 5,
    maxLeagues: 9,
    maxTeamsPerLeague: 999,
    isPopular: true,
    unlimitedMasterLeagues: false,
    unlimitedCompetitions: false,
  ),
  elite(
    id: 'elite',
    displayName: 'Elite',
    description: 'Unlimited master leagues and competitions',
    maxMasterLeagues: 999,
    maxLeagues: 999,
    maxTeamsPerLeague: 999,
    isPopular: false,
    unlimitedMasterLeagues: true,
    unlimitedCompetitions: true,
  );

  const MasterLeaguePlan({
    required this.id,
    required this.displayName,
    required this.description,
    required this.maxMasterLeagues,
    required this.maxLeagues,
    required this.maxTeamsPerLeague,
    required this.isPopular,
    required this.unlimitedMasterLeagues,
    required this.unlimitedCompetitions,
  });

  final String id;
  final String displayName;
  final String description;
  final int maxMasterLeagues;
  final int maxLeagues;
  final int maxTeamsPerLeague;
  final bool isPopular;
  final bool unlimitedMasterLeagues;
  final bool unlimitedCompetitions;

  bool get isBasic => this == basic;
  bool get isPro => this == pro;
  bool get isElite => this == elite;

  static MasterLeaguePlan fromString(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) return value;
    }
    return basic;
  }
}
