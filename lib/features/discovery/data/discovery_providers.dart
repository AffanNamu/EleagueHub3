// lib/features/discovery/data/discovery_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leagues/models/league.dart';

/// Public leagues for the Discovery Hub's "Competitions" destination.
///
/// A league qualifies here purely based on the privacy choice the
/// organizer made at creation time (League.isPrivate == false) — the
/// same public/private toggle already surfaced during league
/// creation, and the same field the Firestore `canReadLeagueDirect()`
/// rule already treats as publicly readable. No separate "featured"
/// or master-league-only filtering — every public league qualifies.
final publicCompetitionsProvider =
    FutureProvider.autoDispose<List<League>>((ref) async {
  final snap = await FirebaseFirestore.instance
      .collection('leagues')
      .where('isPrivate', isEqualTo: false)
      .orderBy('updatedAtMs', descending: true)
      .limit(30)
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 15));

  final out = <League>[];
  for (final doc in snap.docs) {
    try {
      final map = <String, dynamic>{...doc.data()};
      if ((map['id'] as String? ?? '').trim().isEmpty) map['id'] = doc.id;
      out.add(League.fromRemoteMap(map));
    } catch (_) {}
  }
  return out;
});
