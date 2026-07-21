import 'package:cloud_firestore/cloud_firestore.dart';

/// Public football identity for a user's team.
/// Lives at users/{uid}/team_profile/profile
///
/// Kept fully separate from UserProfile (account identity: username,
/// shareId, badges, subscription). This document is what visitors see.
class TeamProfile {
  const TeamProfile({
    required this.userId,
    required this.game,
    required this.favoriteClub,
    required this.favoritePlayer,
    required this.bio,
    required this.bannerImageUrl,
    required this.themeColor,
    required this.visibility,
    required this.updatedAtMs,
  });

  final String userId;

  /// One of GameId.values (see game_id.dart). Stored as string for
  /// forward-compatibility — new games never require a migration.
  final String game;

  final String favoriteClub;
  final String favoritePlayer;
  final String bio;
  final String bannerImageUrl;

  /// Hex string, e.g. "#B6FF00". Empty = use app default accent.
  final String themeColor;

  /// 'public' | 'followers_only' | 'private'
  final String visibility;

  final int updatedAtMs;

  factory TeamProfile.empty(String userId) {
    return TeamProfile(
      userId: userId,
      game: 'local_football',
      favoriteClub: '',
      favoritePlayer: '',
      bio: '',
      bannerImageUrl: '',
      themeColor: '',
      visibility: 'public',
      updatedAtMs: 0,
    );
  }

  factory TeamProfile.fromMap(String userId, Map<String, dynamic> map) {
    return TeamProfile(
      userId: userId,
      game: (map['game'] as String? ?? 'local_football').trim(),
      favoriteClub: (map['favoriteClub'] as String? ?? '').trim(),
      favoritePlayer: (map['favoritePlayer'] as String? ?? '').trim(),
      bio: (map['bio'] as String? ?? '').trim(),
      bannerImageUrl: (map['bannerImageUrl'] as String? ?? '').trim(),
      themeColor: (map['themeColor'] as String? ?? '').trim(),
      visibility: (map['visibility'] as String? ?? 'public').trim(),
      updatedAtMs: _asInt(map['updatedAtMs']),
    );
  }

  factory TeamProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TeamProfile.fromMap(doc.reference.parent.parent!.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() => {
        'game': game,
        'favoriteClub': favoriteClub.trim(),
        'favoritePlayer': favoritePlayer.trim(),
        'bio': bio.trim(),
        'bannerImageUrl': bannerImageUrl.trim(),
        'themeColor': themeColor.trim(),
        'visibility': visibility,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

  TeamProfile copyWith({
    String? game,
    String? favoriteClub,
    String? favoritePlayer,
    String? bio,
    String? bannerImageUrl,
    String? themeColor,
    String? visibility,
  }) {
    return TeamProfile(
      userId: userId,
      game: game ?? this.game,
      favoriteClub: favoriteClub ?? this.favoriteClub,
      favoritePlayer: favoritePlayer ?? this.favoritePlayer,
      bio: bio ?? this.bio,
      bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      themeColor: themeColor ?? this.themeColor,
      visibility: visibility ?? this.visibility,
      updatedAtMs: updatedAtMs,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
