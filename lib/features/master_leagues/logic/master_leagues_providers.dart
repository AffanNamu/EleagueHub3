import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/master_leagues_repository_firebase.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import 'master_league_entitlement_service.dart';
import 'master_league_payment_service.dart';

class _ConcreteMasterLeaguePaymentService extends MasterLeaguePaymentService {
  _ConcreteMasterLeaguePaymentService();
}

final masterLeaguesRepositoryProvider =
    Provider<MasterLeaguesRepositoryFirebase>((ref) {
  return MasterLeaguesRepositoryFirebase();
});

final myMasterLeaguesProvider =
    StreamProvider.autoDispose<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchMyMasterLeagues();
});

final masterLeagueByIdProvider =
    FutureProvider.autoDispose.family<MasterLeague?, String>((ref, id) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.getById(id);
});

final masterLeagueEntitlementServiceProvider =
    Provider<MasterLeagueEntitlementService>((ref) {
  return MasterLeagueEntitlementService();
});

final masterLeaguePaymentServiceProvider =
    Provider<MasterLeaguePaymentService>((ref) {
  return _ConcreteMasterLeaguePaymentService();
});

final masterLeagueUnlockedProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.watchUnlocked();
});

final organizerProUnlockedProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.watchUnlocked();
});

final organizerProActivePlanProvider =
    StreamProvider.autoDispose<MasterLeaguePlan?>((ref) {
  final svc = ref.watch(masterLeagueEntitlementServiceProvider);

  return FirebaseAuth.instance.idTokenChanges().asyncMap((_) async {
    try {
      return await svc.getActivePlan(forceRefresh: false);
    } catch (_) {
      return null;
    }
  });
});

final organizerProPlanProvider =
    FutureProvider.autoDispose<MasterLeaguePlan?>((ref) async {
  final svc = ref.watch(masterLeagueEntitlementServiceProvider);
  try {
    return await svc.getActivePlan(forceRefresh: false);
  } catch (_) {
    return null;
  }
});
