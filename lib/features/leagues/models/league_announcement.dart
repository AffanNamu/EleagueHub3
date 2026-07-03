import 'package:cloud_firestore/cloud_firestore.dart';

/// Announcement model used by the app.
///
/// Supports BOTH:
/// 1) League announcements:
///    - scope: 'league'
///    - leagueId: non-empty (usually)
///    - masterLeagueId: ''
///
/// 2) Organizer/Master league announcements:
///    - scope: 'master_league'
///    - masterLeagueId: non-empty (usually)
///    - leagueId: '' (by convention in your repository)
///
/// IMPORTANT (Backward Compatibility):
/// This model is intentionally permissive because older screens (e.g.
/// league_admin_screen.dart) may construct LeagueAnnouncement without
/// providing fields like authorId/authorName/masterLeagueId/scope.
/// Validation is enforced at the repository + Firestore rules layer.
class LeagueAnnouncement {
  const LeagueAnnouncement({
    this.id = '',
    this.leagueId = '',
    this.masterLeagueId = '',
    this.scope = 'league',
    this.title = '',
    this.message = '',
    this.createdAtMs = 0,
    this.authorId = '',
    this.authorName = '',
    this.pinned = false,
    this.pinnedAtMs = 0,
    this.pinnedBy = '',
  });

  /// Firestore document id. Can be empty; repository may generate one.
  final String id;

  /// League ID for regular league announcements.
  final String leagueId;

  /// Master league ID for organizer announcements.
  final String masterLeagueId;

  /// 'league' or 'master_league'
  final String scope;

  final String title;
  final String message;

  final int createdAtMs;

  /// Author fields may be empty in some older call-sites; repository/rules
  /// enforce correctness when actually writing to Firestore.
  final String authorId;
  final String authorName;

  final bool pinned;
  final int pinnedAtMs;
  final String pinnedBy;

  // ───────────────────────────────────────────────────────────────────────────
  // Serialization
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id.trim(),
      'leagueId': leagueId.trim(),
      'masterLeagueId': masterLeagueId.trim(),
      'scope': scope.trim().isEmpty ? 'league' : scope.trim(),
      'title': title.trim(),
      'message': message.trim(),
      'createdAtMs': createdAtMs,
      'authorId': authorId.trim(),
      'authorName': authorName.trim(),
      'pinned': pinned,
      'pinnedAtMs': pinnedAtMs,
      'pinnedBy': pinnedBy.trim(),
    };
  }

  factory LeagueAnnouncement.fromMap(Map<String, dynamic> map) {
    return LeagueAnnouncement(
      id: (map['id'] as String? ?? '').trim(),
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      masterLeagueId: (map['masterLeagueId'] as String? ?? '').trim(),
      scope: ((map['scope'] as String?) ?? 'league').trim().isEmpty
          ? 'league'
          : ((map['scope'] as String?) ?? 'league').trim(),
      title: (map['title'] as String? ?? '').trim(),
      message: (map['message'] as String? ?? '').trim(),
      createdAtMs: _readMs(map['createdAtMs']),
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorName: (map['authorName'] as String? ?? '').trim(),
      pinned: (map['pinned'] as bool?) ?? false,
      pinnedAtMs: _readMs(map['pinnedAtMs']),
      pinnedBy: (map['pinnedBy'] as String? ?? '').trim(),
    );
  }

  static int _readMs(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is Timestamp) return raw.toDate().millisecondsSinceEpoch;
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return 0;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // copyWith
  // ───────────────────────────────────────────────────────────────────────────

  LeagueAnnouncement copyWith({
    String? id,
    String? leagueId,
    String? masterLeagueId,
    String? scope,
    String? title,
    String? message,
    int? createdAtMs,
    String? authorId,
    String? authorName,
    bool? pinned,
    int? pinnedAtMs,
    String? pinnedBy,
  }) {
    return LeagueAnnouncement(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      scope: scope ?? this.scope,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      pinned: pinned ?? this.pinned,
      pinnedAtMs: pinnedAtMs ?? this.pinnedAtMs,
      pinnedBy: pinnedBy ?? this.pinnedBy,
    );
  }

  @override
  String toString() {
    return 'LeagueAnnouncement(id=$id, scope=$scope, leagueId=$leagueId, masterLeagueId=$masterLeagueId, pinned=$pinned)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LeagueAnnouncement && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}