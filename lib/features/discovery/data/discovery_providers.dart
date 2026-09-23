// lib/features/discovery/data/discovery_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leagues/models/football_category.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_format.dart';

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

/// Real total counts of public leagues per football category, for the
/// "Browse by category" section on Home. Uses Firestore's server-side
/// count() aggregation (exact totals, no documents downloaded) rather
/// than counting publicCompetitionsProvider's capped 30-item list.
///
/// Each query is equality-only (isPrivate == false AND footballCategory
/// == X, no orderBy) -- deliberately avoids needing a composite index,
/// unlike an equality+orderBy combination.
final footballCategoryCountsProvider =
    FutureProvider.autoDispose<Map<FootballCategory, int>>((ref) async {
  final col = FirebaseFirestore.instance.collection('leagues');

  final entries = await Future.wait(FootballCategory.values.map((c) async {
    try {
      final agg = await col
          .where('isPrivate', isEqualTo: false)
          .where('footballCategory', isEqualTo: c.storageValue)
          .count()
          .get()
          .timeout(const Duration(seconds: 12));
      return MapEntry(c, agg.count ?? 0);
    } catch (_) {
      return MapEntry(c, 0);
    }
  }));

  return Map<FootballCategory, int>.fromEntries(entries);
});

/// Real total counts of public leagues per format (Classic, Group,
/// Series, World Cup, Direct Knockout), for the "Browse by type"
/// section on Home. Same equality-only count() approach as
/// [footballCategoryCountsProvider] -- no composite index needed.
final leagueFormatCountsProvider =
    FutureProvider.autoDispose<Map<LeagueFormat, int>>((ref) async {
  final col = FirebaseFirestore.instance.collection('leagues');

  final entries = await Future.wait(LeagueFormat.values.map((f) async {
    try {
      final agg = await col
          .where('isPrivate', isEqualTo: false)
          .where('format', isEqualTo: f.index)
          .count()
          .get()
          .timeout(const Duration(seconds: 12));
      return MapEntry(f, agg.count ?? 0);
    } catch (_) {
      return MapEntry(f, 0);
    }
  }));

  return Map<LeagueFormat, int>.fromEntries(entries);
});
