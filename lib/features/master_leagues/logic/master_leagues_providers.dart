import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/master_leagues_repository_firebase.dart';
import 'master_league_entitlement_service.dart';

final masterLeaguesRepositoryProvider = Provider<MasterLeaguesRepositoryFirebase>((ref) {
  return MasterLeaguesRepositoryFirebase();
});

final myMasterLeaguesProvider = StreamProvider.autoDispose((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchMyMasterLeagues();
});

final masterLeagueEntitlementServiceProvider = Provider<MasterLeagueEntitlementService>((ref) {
  return MasterLeagueEntitlementService();
});

final masterLeagueUnlockedProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.watchUnlocked();
});
