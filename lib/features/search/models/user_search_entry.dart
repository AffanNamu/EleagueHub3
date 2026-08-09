//lib/features/search/models/UserSearchEntry
import 'package:cloud_firestore/cloud_firestore.dart';

class UserSearchEntry {
  const UserSearchEntry({
    required this.userId,
    required this.displayName,
    required this.shareId,
    required this.game,
    required this.badge,
    required this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String shareId;
  final String game;
  final String badge;
  final String avatarUrl;

  factory UserSearchEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return UserSearchEntry(
      userId: doc.id,
      displayName: (map['displayName'] as String? ?? '').trim(),
      shareId: (map['shareId'] as String? ?? '').trim(),
      game: (map['game'] as String? ?? '').trim(),
      badge: (map['badge'] as String? ?? '').trim(),
      avatarUrl: (map['avatarUrl'] as String? ?? '').trim(),
    );
  }
}
