import 'league_format.dart';

/// Sync status for offline-first leagues
enum SyncStatus {
  pending,   // Local change not yet uploaded
  synced,    // In sync with server
  failed,    // Tried but failed to sync
  conflict,  // Conflict detected (admin vs local)
}

/// Identifies where the last edit came from
enum SyncSource {
  local,
  admin,
  cloud,
}

/// Represents a league that can exist offline and sync later.
class LocalLeague {
  final String id;
  final String name;
  final LeagueFormat format;

  /// Sync metadata
  final SyncStatus syncStatus;
  final SyncSource source;

  /// Timestamps (millisecondsSinceEpoch)
  final int lastModified;
  final int? lastSyncedAt;

  const LocalLeague({
    required this.id,
    required this.name,
    required this.format,
    this.syncStatus = SyncStatus.pending,
    this.source = SyncSource.local,
    required this.lastModified,
    this.lastSyncedAt,
  });

  LocalLeague copyWith({
    String? name,
    LeagueFormat? format,
    SyncStatus? syncStatus,
    SyncSource? source,
    int? lastModified,
    int? lastSyncedAt,
  }) {
    return LocalLeague(
      id: id,
      name: name ?? this.name,
      format: format ?? this.format,
      syncStatus: syncStatus ?? this.syncStatus,
      source: source ?? this.source,
      lastModified: lastModified ?? this.lastModified,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'format': format.index,
        'syncStatus': syncStatus.index,
        'source': source.index,
        'lastModified': lastModified,
        'lastSyncedAt': lastSyncedAt,
      };

  static LocalLeague fromMap(Map<String, dynamic> map) {
    return LocalLeague(
      id: map['id'],
      name: map['name'],
      format: LeagueFormat.values[map['format']],
      syncStatus: SyncStatus.values[
          map['syncStatus'] ?? SyncStatus.pending.index],
      source: SyncSource.values[
          map['source'] ?? SyncSource.local.index],
      lastModified: map['lastModified'],
      lastSyncedAt: map['lastSyncedAt'],
    );
  }
}
