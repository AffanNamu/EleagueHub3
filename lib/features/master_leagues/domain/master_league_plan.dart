/// Master League subscription tiers.
///
/// Basic  — 5 leagues, 5 teams per league
/// Pro    — 5 leagues, 12 teams per league (most popular)
/// Elite  — unlimited leagues, unlimited teams
enum MasterLeaguePlan {
  basic,
  pro,
  elite;

  String get id {
    switch (this) {
      case MasterLeaguePlan.basic:
        return 'basic';
      case MasterLeaguePlan.pro:
        return 'pro';
      case MasterLeaguePlan.elite:
        return 'elite';
    }
  }

  String get displayName {
    switch (this) {
      case MasterLeaguePlan.basic:
        return 'Basic';
      case MasterLeaguePlan.pro:
        return 'Pro';
      case MasterLeaguePlan.elite:
        return 'Elite';
    }
  }

  String get description {
    switch (this) {
      case MasterLeaguePlan.basic:
        return '5 leagues • 5 teams per league';
      case MasterLeaguePlan.pro:
        return '5 leagues • 12 teams per league';
      case MasterLeaguePlan.elite:
        return 'Unlimited leagues • Unlimited teams';
    }
  }

  /// Max leagues allowed inside a single Master League.
  int get maxLeagues {
    switch (this) {
      case MasterLeaguePlan.basic:
        return 5;
      case MasterLeaguePlan.pro:
        return 5;
      case MasterLeaguePlan.elite:
        return 999; // effectively unlimited
    }
  }

  /// Max teams per league inside the Master League.
  int get maxTeamsPerLeague {
    switch (this) {
      case MasterLeaguePlan.basic:
        return 5;
      case MasterLeaguePlan.pro:
        return 12;
      case MasterLeaguePlan.elite:
        return 999; // effectively unlimited
    }
  }

  bool get isPopular => this == MasterLeaguePlan.pro;

  static MasterLeaguePlan fromString(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    switch (v) {
      case 'pro':
        return MasterLeaguePlan.pro;
      case 'elite':
        return MasterLeaguePlan.elite;
      case 'basic':
      default:
        return MasterLeaguePlan.basic;
    }
  }
}
