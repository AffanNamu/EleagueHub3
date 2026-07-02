// lib/features/leagues/models/league_settings.dart
//
// MODIFIED: Added worldCupTeamCount (32 or 48) to support FIFA 2022 and 2026 formats.
// Fully backward-compatible — old Firestore documents without these fields
// will deserialize with safe defaults (32 teams = FIFA 2022 format).

import 'dart:convert';

import 'league_format.dart';

/// The two official FIFA World Cup formats supported by this engine.
///
/// - [fifa2022] → 32 teams, 8 groups of 4, R16 → QF → SF → 3rd Place → Final
/// - [fifa2026] → 48 teams, 12 groups of 4, R32 → R16 → QF → SF → 3rd Place → Final
enum WorldCupFormat {
  fifa2022, // 32 teams — classic FIFA World Cup format
  fifa2026, // 48 teams — expanded FIFA World Cup 2026 format
}

extension WorldCupFormatX on WorldCupFormat {
  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case WorldCupFormat.fifa2022:
        return 'FIFA World Cup 2022 Format (32 Teams)';
      case WorldCupFormat.fifa2026:
        return 'FIFA World Cup 2026 Format (48 Teams)';
    }
  }

  /// Short description shown beneath the option card.
  String get description {
    switch (this) {
      case WorldCupFormat.fifa2022:
        return '8 groups of 4 teams. Top 2 from each group advance to '
            'Round of 16. Then Quarter-finals, Semi-finals, '
            'Third Place match, and Final.';
      case WorldCupFormat.fifa2026:
        return '12 groups of 4 teams. Top 2 from each group plus 8 best '
            'third-placed teams advance to Round of 32. Then Round of 16, '
            'Quarter-finals, Semi-finals, Third Place match, and Final.';
    }
  }

  /// Total number of teams in this format.
  int get teamCount {
    switch (this) {
      case WorldCupFormat.fifa2022:
        return 32;
      case WorldCupFormat.fifa2026:
        return 48;
    }
  }

  /// Number of groups in this format.
  int get groupCount {
    switch (this) {
      case WorldCupFormat.fifa2022:
        return 8;
      case WorldCupFormat.fifa2026:
        return 12;
    }
  }

  /// Teams per group (always 4 in both formats).
  int get teamsPerGroup => 4;

  /// Serialization key stored in Firestore.
  String get firestoreKey {
    switch (this) {
      case WorldCupFormat.fifa2022:
        return 'fifa2022';
      case WorldCupFormat.fifa2026:
        return 'fifa2026';
    }
  }

  /// Deserialize from a Firestore string value.
  static WorldCupFormat fromString(String? raw) {
    if (raw == null) return WorldCupFormat.fifa2022;
    switch (raw.trim().toLowerCase()) {
      case 'fifa2026':
      case '48':
        return WorldCupFormat.fifa2026;
      default:
        // Safe fallback: classic 32-team format.
        return WorldCupFormat.fifa2022;
    }
  }
}

class LeagueSettings {
  final bool doubleRoundRobin;

  /// UCL Group only (supported: groups of 4)
  final int groupSize;

  /// UCL Swiss only (supported: 8 matches per team)
  final int swissRounds;

  final int lastPulledAtMs;

  /// World Cup only — which FIFA format to use.
  ///
  /// Stored as a string in Firestore ('fifa2022' or 'fifa2026').
  /// Ignored for non-World Cup leagues.
  /// Backward compatible: absent in old Firestore docs → defaults to fifa2022.
  final WorldCupFormat worldCupFormat;

  const LeagueSettings({
    required this.doubleRoundRobin,
    required this.groupSize,
    required this.swissRounds,
    required this.lastPulledAtMs,
    this.worldCupFormat = WorldCupFormat.fifa2022,
  });

  /// Defaults per format.
  ///
  /// NOTE: Competition rules enforced elsewhere require:
  /// - UCL Group: groupSize = 4
  /// - UCL Swiss: swissRounds = 8 (8 opponents)
  /// - World Cup: groupSize = 4, worldCupFormat = fifa2022 (default)
  factory LeagueSettings.defaultsFor(LeagueFormat format) {
    switch (format) {
      case LeagueFormat.classic:
        return const LeagueSettings(
          doubleRoundRobin: true,
          groupSize: 4,
          swissRounds: 8,
          lastPulledAtMs: 0,
          worldCupFormat: WorldCupFormat.fifa2022,
        );
      case LeagueFormat.uclGroup:
        return const LeagueSettings(
          doubleRoundRobin: true,
          groupSize: 4,
          swissRounds: 8,
          lastPulledAtMs: 0,
          worldCupFormat: WorldCupFormat.fifa2022,
        );
      case LeagueFormat.uclSwiss:
        return const LeagueSettings(
          doubleRoundRobin: true,
          groupSize: 4,
          swissRounds: 8,
          lastPulledAtMs: 0,
          worldCupFormat: WorldCupFormat.fifa2022,
        );
      case LeagueFormat.worldCup:
        // World Cup uses single round-robin in groups (each team plays 3 games).
        return const LeagueSettings(
          doubleRoundRobin: false,
          groupSize: 4,
          swissRounds: 8,
          lastPulledAtMs: 0,
          worldCupFormat: WorldCupFormat.fifa2022,
        );
    }
  }

  /// Alias to fix the repository error while keeping your logic.
  factory LeagueSettings.defaultSettings() =>
      LeagueSettings.defaultsFor(LeagueFormat.classic);

  LeagueSettings copyWith({
    bool? doubleRoundRobin,
    int? groupSize,
    int? swissRounds,
    int? lastPulledAtMs,
    WorldCupFormat? worldCupFormat,
  }) {
    return LeagueSettings(
      doubleRoundRobin: doubleRoundRobin ?? this.doubleRoundRobin,
      groupSize: groupSize ?? this.groupSize,
      swissRounds: swissRounds ?? this.swissRounds,
      lastPulledAtMs: lastPulledAtMs ?? this.lastPulledAtMs,
      worldCupFormat: worldCupFormat ?? this.worldCupFormat,
    );
  }

  Map<String, dynamic> toMap() => {
        'doubleRoundRobin': doubleRoundRobin,
        'groupSize': groupSize,
        'swissRounds': swissRounds,
        'lastPulledAtMs': lastPulledAtMs,
        // Only write worldCupFormat when it has meaning to avoid
        // polluting non-World Cup league documents unnecessarily.
        'worldCupFormat': worldCupFormat.firestoreKey,
      };

  factory LeagueSettings.fromMap(Map<String, dynamic> map) {
    return LeagueSettings(
      doubleRoundRobin: (map['doubleRoundRobin'] as bool?) ?? true,
      groupSize: (map['groupSize'] as num?)?.toInt() ?? 4,
      swissRounds: (map['swissRounds'] as num?)?.toInt() ?? 8,
      lastPulledAtMs: (map['lastPulledAtMs'] as num?)?.toInt() ?? 0,
      // Backward compatible: absent in old docs → defaults to fifa2022.
      worldCupFormat: WorldCupFormatX.fromString(
        map['worldCupFormat'] as String?,
      ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory LeagueSettings.fromJson(String json) {
    if (json.trim().isEmpty) {
      return const LeagueSettings(
        doubleRoundRobin: true,
        groupSize: 4,
        swissRounds: 8,
        lastPulledAtMs: 0,
        worldCupFormat: WorldCupFormat.fifa2022,
      );
    }
    return LeagueSettings.fromMap(
        jsonDecode(json) as Map<String, dynamic>);
  }
}