// lib/features/leagues/models/league_announcement.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Announcement document.
///
/// Used for both regular league announcements (leagueId set) and
/// master league / organizer announcements (masterLeagueId set).
///
/// Fields added vs original:
///   masterLeagueId — identifies the owning master league
///   pinned         — whether this announcement is pinned
///   pinnedAtMs     — when it was pinned (ms since epoch)
///   pinnedBy       — uid of who pinned it
///   updatedAtMs    — last update timestamp
///
/// All new fields default safely so existing code that constructs
/// LeagueAnnouncement without them continues to compile.
class LeagueAnnouncement {
  const LeagueAnnouncement({
    required this.id,
    required this.leagueId,
    required this.masterLeagueId,
    required this.title,
    required this.message,
    required this.authorId,
    required this.authorName,
    required this.pinned,
    required this.pinnedAtMs,
    required this.pinnedBy,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;

  /// Set when this belongs to a regular league.
  final String leagueId;

  /// Set when this belongs to a master league workspace.
  final String masterLeagueId;

  final String title;
  final String message;
  final String authorId;
  final String authorName;

  /// True when this announcement is currently pinned.
  final bool pinned;

  /// Milliseconds since epoch when pinned. 0 if not pinned.
  final int pinnedAtMs;

  /// UID of the user who pinned this announcement.
  final String pinnedBy;

  final int createdAtMs;
  final int updatedAtMs;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'leagueId': leagueId,
      'masterLeagueId': masterLeagueId,
      'title': title,
      'message': message,
      'authorId': authorId,
      'authorName': authorName,
      'pinned': pinned,
      'pinnedAtMs': pinnedAtMs,
      'pinnedBy': pinnedBy,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  factory LeagueAnnouncement.fromMap(Map<String, dynamic> map) {
    return LeagueAnnouncement(
      id: (map['id'] as String? ?? '').trim(),
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      masterLeagueId:
          (map['masterLeagueId'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      message: (map['message'] as String? ?? '').trim(),
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorName: (map['authorName'] as String? ?? '').trim(),
      pinned: (map['pinned'] as bool?) ?? false,
      pinnedAtMs: _readMs(map['pinnedAtMs']),
      pinnedBy: (map['pinnedBy'] as String? ?? '').trim(),
      createdAtMs: _readMs(map['createdAtMs']),
      updatedAtMs: _readMs(map['updatedAtMs']),
    );
  }

  static int _readMs(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is Timestamp) {
      return raw.toDate().millisecondsSinceEpoch;
    }
    return 0;
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  LeagueAnnouncement copyWith({
    String? id,
    String? leagueId,
    String? masterLeagueId,
    String? title,
    String? message,
    String? authorId,
    String? authorName,
    bool? pinned,
    int? pinnedAtMs,
    String? pinnedBy,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return LeagueAnnouncement(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      title: title ?? this.title,
      message: message ?? this.message,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      pinned: pinned ?? this.pinned,
      pinnedAtMs: pinnedAtMs ?? this.pinnedAtMs,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LeagueAnnouncement && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}