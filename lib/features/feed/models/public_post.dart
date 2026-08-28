// lib/features/feed/models/public_post.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// The kind of content a public post represents. Extensible by design —
/// adding a new type later does not require touching existing posts.
enum PublicPostType {
  text,
  competitionPromo,
  matchResult,
}

extension PublicPostTypeX on PublicPostType {
  String get storageValue {
    switch (this) {
      case PublicPostType.text:
        return 'text';
      case PublicPostType.competitionPromo:
        return 'competition_promo';
      case PublicPostType.matchResult:
        return 'match_result';
    }
  }

  static PublicPostType fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'competition_promo':
        return PublicPostType.competitionPromo;
      case 'match_result':
        return PublicPostType.matchResult;
      default:
        return PublicPostType.text;
    }
  }
}

/// A public community feed post (Feature 3 — Public Feed).
/// Firestore path: public_posts/{postId}
///
/// Kept as its own top-level collection — separate from Status and
/// team_profile — so post lifetime, moderation, and future promotion
/// logic can evolve independently of the other two systems.
class PublicPost {
  const PublicPost({
    required this.postId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.createdAtMs,
    required this.text,
    required this.mediaUrl,
    required this.audioUrl, // NEW: Audio support
    required this.postType,
    required this.leagueId,
    required this.leagueName,
    required this.matchScoreHome,
    required this.matchScoreAway,
    required this.matchOpponentName,
    required this.isPromoted,
    required this.likeCount,
    required this.commentCount,
    required this.deleted,
  });

  final String postId;
  final String authorId;
  final String authorDisplayName;
  final String authorPhotoUrl;
  final int createdAtMs;
  final String text;
  final String mediaUrl;
  final String audioUrl; // NEW: Audio support
  final PublicPostType postType;

  /// Optional — populated for competitionPromo / matchResult posts so
  /// the card can deep-link into the real league.
  final String leagueId;
  final String leagueName;

  /// Optional — only meaningful for postType == matchResult.
  final int matchScoreHome;
  final int matchScoreAway;
  final String matchOpponentName;

  /// Reserved for future organizer-promotion (see rules #13). Always
  /// false today — no promotion purchase flow exists yet.
  final bool isPromoted;

  final int likeCount;
  final int commentCount;
  final bool deleted;

  factory PublicPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return PublicPost(
      postId: doc.id,
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorDisplayName: (map['authorDisplayName'] as String? ?? '').trim(),
      authorPhotoUrl: (map['authorPhotoUrl'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
      text: (map['text'] as String? ?? '').trim(),
      mediaUrl: (map['mediaUrl'] as String? ?? '').trim(),
      audioUrl: (map['audioUrl'] as String? ?? '').trim(), // NEW: Audio support
      postType: PublicPostTypeX.fromStorage(map['postType'] as String?),
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      leagueName: (map['leagueName'] as String? ?? '').trim(),
      matchScoreHome: _asInt(map['matchScoreHome']),
      matchScoreAway: _asInt(map['matchScoreAway']),
      matchOpponentName: (map['matchOpponentName'] as String? ?? '').trim(),
      isPromoted: map['isPromoted'] == true,
      likeCount: _asInt(map['likeCount']),
      commentCount: _asInt(map['commentCount']),
      deleted: map['deleted'] == true,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}