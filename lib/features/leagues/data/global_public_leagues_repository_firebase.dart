import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/global_public_league.dart';
import '../models/league.dart';

class GlobalPublicLeaguesRepositoryFirebase {
  GlobalPublicLeaguesRepositoryFirebase({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _leaguesCol =>
      _firestore.collection('leagues').withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => (snap.data() ?? <String, dynamic>{}),
            toFirestore: (map, _) => map,
          );

  Query<Map<String, dynamic>> _publicLeaguesQuery({required int limit}) {
    // Stored format in this app is typically:
    // - isPrivate: 1/0 (int) from League.toJson()
    // But we also support boolean for forward-compatibility.
    //
    // NOTE:
    // This query requires a composite index for:
    //   isPrivate (ASC) + updatedAtMs (DESC)
    return _leaguesCol
        .where('isPrivate', whereIn: const [0, false])
        .orderBy('updatedAtMs', descending: true)
        .limit(limit);
  }

  Stream<List<GlobalPublicLeague>> watchLatestPublicLeagues({
    int limit = 100,
  }) {
    return _publicLeaguesQuery(limit: limit).snapshots().map((snapshot) {
      final items = <GlobalPublicLeague>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Ensure id is always present for navigation.
        data['id'] = (data['id'] is String && (data['id'] as String).trim().isNotEmpty) ? data['id'] : doc.id;

        final league = League.fromRemoteMap(data);

        // Extra optional fields (global-discovery only)
        final registeredCount = (data['registeredCount'] as num?)?.toInt() ??
            (data['participantCount'] as num?)?.toInt() ??
            (data['membersCount'] as num?)?.toInt();

        final isFullStored = data['isFull'] == true || data['isFull'] == 1;

        // Finished flag (optional, backward compatible)
        final isFinishedStored = data['isFinished'] == true || data['isFinished'] == 1;

        final item = GlobalPublicLeague(
          league: league,
          registeredCount: registeredCount,
          isFullStored: isFullStored,
          isFinishedStored: isFinishedStored,
        );

        // Enforce visibility rules:
        // - public only
        // - finished leagues should not appear
        // - NOTE: we DO NOT hide full leagues anymore (per updated requirement)
        if (!item.isPublic) continue;
        if (item.isFinished) continue;

        items.add(item);
      }

      return items;
    });
  }
}
