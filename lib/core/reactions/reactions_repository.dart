// lib/core/reactions/reactions_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'message_reaction.dart';

/// Generic emoji-reaction repository usable against ANY message/post doc
/// across the app's reaction surfaces (global/league/organizer chat,
/// private DM messages, feed posts) -- all five share the identical
/// `<parent>/reactions/{uid}` subcollection shape validated by
/// firestore.rules' validReactionCreate(), so one implementation covers
/// every caller rather than duplicating this per surface.
class ReactionsRepository {
  ReactionsRepository(this._parentRef, {FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final DocumentReference<Map<String, dynamic>> _parentRef;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _reactionsCol =>
      _parentRef.collection('reactions');

  String? get _uid => _auth.currentUser?.uid;

  Stream<ReactionSummary> watch() {
    return _reactionsCol.snapshots().map((snap) {
      final reactions = snap.docs.map(MessageReaction.fromDoc).toList();
      return ReactionSummary.fromReactions(reactions, _uid);
    });
  }

  /// Sets the caller's reaction to [emoji]. Tapping the same emoji again
  /// removes it (toggle-off); picking a different one replaces it -- one
  /// reaction per user per message, like Messenger/Discord rather than
  /// Slack's multi-reaction-per-user model.
  Future<void> toggle(String emoji) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    final ref = _reactionsCol.doc(uid);
    final existing = await ref.get();
    if (existing.exists && (existing.data()?['emoji'] as String?) == emoji) {
      await ref.delete();
    } else {
      await ref.set({
        'uid': uid,
        'emoji': emoji,
        'reactedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }
}
