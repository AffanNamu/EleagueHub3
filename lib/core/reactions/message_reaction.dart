// lib/core/reactions/message_reaction.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// The fixed emoji palette for reactions -- must stay in sync with
/// firestore.rules' validReactionEmoji() allowlist.
const List<String> kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '👏'];

/// One user's reaction on a message/post. Firestore path is always
/// `<parent>/reactions/{uid}` -- the doc id IS the reacting user's uid, so
/// a user can only ever hold one reaction per message at a time.
class MessageReaction {
  final String uid;
  final String emoji;
  final int reactedAtMs;

  const MessageReaction({
    required this.uid,
    required this.emoji,
    required this.reactedAtMs,
  });

  factory MessageReaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MessageReaction(
      uid: (data['uid'] as String?) ?? doc.id,
      emoji: (data['emoji'] as String?) ?? '',
      reactedAtMs: (data['reactedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'emoji': emoji,
        'reactedAtMs': reactedAtMs,
      };
}

/// Grouped view of a message/post's reactions, as consumed by UI widgets.
class ReactionSummary {
  /// emoji -> how many users picked it.
  final Map<String, int> counts;

  /// The signed-in user's own reaction, if any.
  final String? myEmoji;

  const ReactionSummary({this.counts = const {}, this.myEmoji});

  static const empty = ReactionSummary();

  int get total => counts.values.fold(0, (a, b) => a + b);
  bool get isEmpty => counts.isEmpty;

  /// Emojis in [kReactionEmojis] order (so the pill row is stable), only
  /// those with at least one reaction.
  List<MapEntry<String, int>> get orderedEntries => kReactionEmojis
      .where(counts.containsKey)
      .map((e) => MapEntry(e, counts[e]!))
      .toList(growable: false);

  static ReactionSummary fromReactions(List<MessageReaction> reactions, String? myUid) {
    final counts = <String, int>{};
    String? mine;
    for (final r in reactions) {
      if (r.emoji.isEmpty) continue;
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (myUid != null && r.uid == myUid) mine = r.emoji;
    }
    return ReactionSummary(counts: counts, myEmoji: mine);
  }
}
