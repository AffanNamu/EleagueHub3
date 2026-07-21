//membership.dart
/// Defines the roles a user can have within a league.
enum LeagueRole { organizer, member }

/// Extension to handle conversion from integer (database) to LeagueRole.
extension LeagueRoleX on LeagueRole {
  static LeagueRole fromInt(int v) => LeagueRole.values[v];
}

/// Represents the connection between a User and a League in eSportlyic.
/// 
/// This model tracks:
/// - The user's role (Organizer vs Member).
/// - Which team the user belongs to (for "My Matches" filtering).
/// - Sync metadata for offline consistency.
class Membership {
  final String id;
  final String leagueId;
  final String userId;

  /// If set, this membership is tied to a team and powers "My Matches".
  final String? teamId;

  final LeagueRole role;

  final int updatedAtMs;
  final int version;

  const Membership({
    required this.id,
    required this.leagueId,
    required this.userId,
    required this.teamId,
    required this.role,
    required this.updatedAtMs,
    required this.version,
  });

  /// Converts the Membership object into a Map for remote database storage.
  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'leagueId': leagueId,
        'userId': userId,
        'teamId': teamId,
        'role': role.index,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  /// Factory to create a Membership object from a remote database Map.
  static Membership fromRemoteMap(Map<String, dynamic> map) {
    return Membership(
      id: map['id'] as String,
      leagueId: map['leagueId'] as String,
      userId: map['userId'] as String,
      teamId: map['teamId'] as String?,
      role: LeagueRoleX.fromInt((map['role'] as num).toInt()),
      updatedAtMs: (map['updatedAtMs'] as num).toInt(),
      version: (map['version'] as num).toInt(),
    );
  }
}
