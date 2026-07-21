///lib/features/leagues/models/league_group.dart.
/// Represents a competitive group within a league (primarily for UCL format).
///
/// In a UCL-style league, teams are divided into groups (e.g., "Group A").
/// This model tracks the group name and its display order via sortIndex.
class LeagueGroup {
  final String id;
  final String leagueId; // The league this group belongs to
  final String name; // e.g., "Group A", "Group B"
  final int sortIndex; // Used to keep Groups in alphabetical order (0, 1, 2...)

  /// Local + remote sync metadata (Last Write Wins)
  final int updatedAtMs;
  final int version;

  const LeagueGroup({
    required this.id,
    required this.leagueId,
    required this.name,
    required this.sortIndex,
    required this.updatedAtMs,
    required this.version,
  });

  /// Converts the LeagueGroup object into a Map for remote database storage.
  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'leagueId': leagueId,
        'name': name,
        'sortIndex': sortIndex,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  /// Factory to create a LeagueGroup object from a remote database Map.
  static LeagueGroup fromRemoteMap(Map<String, dynamic> map) {
    return LeagueGroup(
      id: map['id'] as String,
      leagueId: map['leagueId'] as String,
      name: map['name'] as String,
      sortIndex: (map['sortIndex'] as num).toInt(),
      updatedAtMs: (map['updatedAtMs'] as num).toInt(),
      version: (map['version'] as num).toInt(),
    );
  }
}
