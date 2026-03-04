import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/match_highlight.dart';

/// League-wide highlights feed using a collectionGroup query:
/// matches/{matchId}/highlights/{highlightId}
///
/// COST NOTE (Firestore):
/// - collectionGroup queries can be more expensive than per-match subcollection reads.
/// - Keep limits small (e.g., 20–50) and avoid multiple feeds on the same screen.
/// - Cache streams per leagueId+limit to avoid rebuild-driven duplicates.
///
/// INDEX NOTE:
/// This query typically requires an index:
/// collectionGroup: highlights
/// fields: leagueId ASC, createdAt DESC
class HighlightsFeedRepositoryFirebase {
  HighlightsFeedRepositoryFirebase({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  final Map<String, Stream<List<MatchHighlight>>> _leagueFeedCache = {};

  Stream<List<MatchHighlight>> watchLeagueHighlights({
    required String leagueId,
    int limit = 25,
  }) {
    final lid = leagueId.trim();
    if (lid.isEmpty) return const Stream<List<MatchHighlight>>.empty();

    final safeLimit = limit.clamp(1, 50);
    final key = '$lid::$safeLimit';

    final cached = _leagueFeedCache[key];
    if (cached != null) return cached;

    final q = _firestore
        .collectionGroup('highlights')
        .where('leagueId', isEqualTo: lid)
        .orderBy('createdAt', descending: true)
        .limit(safeLimit);

    final stream = q.snapshots(includeMetadataChanges: true).map((snap) {
      return snap.docs.map((d) => MatchHighlight.fromDoc(d)).toList(growable: false);
    });

    _leagueFeedCache[key] = stream;
    return stream;
  }

  void clearCache() => _leagueFeedCache.clear();
}
