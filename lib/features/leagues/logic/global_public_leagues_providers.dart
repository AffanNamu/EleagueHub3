import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../data/global_public_leagues_repository_firebase.dart';
import '../data/leagues_repository_local.dart';
import '../domain/models/global_public_league.dart';
import 'global_public_league_join_service.dart';

final globalPublicLeaguesRepositoryProvider = Provider<GlobalPublicLeaguesRepositoryFirebase>((ref) {
  return GlobalPublicLeaguesRepositoryFirebase(
    firestore: FirebaseFirestore.instance,
  );
});

/// Global discovery stream:
/// - PUBLIC leagues only (filtered in repository)
/// - finished leagues excluded (filtered in repository)
/// - realtime via Firestore snapshots
final globalPublicLeaguesStreamProvider = StreamProvider.autoDispose<List<GlobalPublicLeague>>((ref) {
  final repo = ref.watch(globalPublicLeaguesRepositoryProvider);
  return repo.watchLatestPublicLeagues(limit: 100);
});

final globalPublicLeagueJoinServiceProvider = Provider<GlobalPublicLeagueJoinService>((ref) {
  final prefs = ref.watch(prefsServiceProvider);
  final localRepo = LocalLeaguesRepository(prefs);

  return GlobalPublicLeagueJoinService(
    firestore: FirebaseFirestore.instance,
    localRepo: localRepo,
  );
});
