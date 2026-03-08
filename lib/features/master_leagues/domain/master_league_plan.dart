/// Tiered plan for a Master League.
///
/// Basic  — 1 master league,  5 competitions inside
/// Pro    — 7 master leagues, 12 competitions inside each  (most popular)
/// Elite  — unlimited master leagues, unlimited competitions
enum MasterLeaguePlan {
  basic(
    id: 'basic',
    displayName: 'Basic',
    description: '1 master league, up to 5 competitions',
    maxMasterLeagues: 1,
    maxLeagues: 5,
    maxTeamsPerLeague: 999,
    isPopular: false,
  ),
  pro(
    id: 'pro',
    displayName: 'Pro',
    description: '7 master leagues, up to 12 competitions each',
    maxMasterLeagues: 7,
    maxLeagues: 12,
    maxTeamsPerLeague: 999,
    isPopular: true,
  ),
  elite(
    id: 'elite',
    displayName: 'Elite',
    description: 'Unlimited master leagues & competitions',
    maxMasterLeagues: 999,
    maxLeagues: 999,
    maxTeamsPerLeague: 999,
    isPopular: false,
  );

  const MasterLeaguePlan({
    required this.id,
    required this.displayName,
    required this.description,
    required this.maxMasterLeagues,
    required this.maxLeagues,
    required this.maxTeamsPerLeague,
    required this.isPopular,
  });

  final String id;
  final String displayName;
  final String description;
  final int maxMasterLeagues;
  final int maxLeagues;
  final int maxTeamsPerLeague;
  final bool isPopular;

  /// Resolve from Firestore string. Falls back to [basic].
  static MasterLeaguePlan fromId(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final p in values) {
      if (p.id == s) return p;
    }
    return basic;
  }
}
