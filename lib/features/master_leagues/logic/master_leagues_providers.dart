import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/master_leagues_repository_firebase.dart';
import '../domain/competition_template.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import 'master_league_entitlement_service.dart';
import 'master_league_payment_service.dart';

final masterLeaguesRepositoryProvider =
    Provider<MasterLeaguesRepositoryFirebase>((ref) {
  return MasterLeaguesRepositoryFirebase();
});

final masterLeagueEntitlementServiceProvider =
    Provider<MasterLeagueEntitlementService>((ref) {
  return MasterLeagueEntitlementService();
});

final masterLeaguePaymentServiceProvider = Provider<MasterLeaguePaymentService>(
  (ref) => ref.watch(masterLeaguePaymentServiceImplProvider),
);

final organizerProActivePlanProvider =
    FutureProvider<MasterLeaguePlan?>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.getActivePlan(forceRefresh: false);
});

final myMasterLeaguesProvider = StreamProvider<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchMyMasterLeagues();
});

final createdMasterLeaguesProvider = StreamProvider<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchCreatedMasterLeagues();
});

final joinedMasterLeaguesProvider = StreamProvider<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchJoinedMasterLeagues();
});

final masterLeagueByIdProvider =
    FutureProvider.family<MasterLeague?, String>((ref, id) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.getById(id);
});

final masterLeagueUnlockedProvider = FutureProvider<bool>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  final plan = await entitlement.getActivePlan(forceRefresh: false);
  return plan != null;
});

final masterLeagueFollowStateProvider =
    StreamProvider.family<bool, String>((ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchIsFollowing(masterLeagueId);
});

final masterLeagueFollowersCountProvider =
    StreamProvider.family<int, String>((ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchFollowersCount(masterLeagueId);
});

final masterLeagueCompetitionTemplatesProvider =
    StreamProvider.family<List<CompetitionTemplate>, String>(
  (ref, masterLeagueId) {
    final repo = ref.watch(masterLeaguesRepositoryProvider);
    return repo.watchCompetitionTemplates(masterLeagueId);
  },
);

final featuredOrganizerWorkspacesProvider =
    FutureProvider<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  try {
    return await repo.discoverFeaturedOrganizers(limit: 8);
  } catch (_) {
    return const <MasterLeague>[];
  }
});

final verifiedOrganizerWorkspacesProvider =
    FutureProvider<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  try {
    return await repo.discoverVerifiedOrganizers(limit: 12);
  } catch (_) {
    return const <MasterLeague>[];
  }
});

final recentActiveOrganizerWorkspacesProvider =
    FutureProvider<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  try {
    return await repo.discoverRecentActiveOrganizers(limit: 12);
  } catch (_) {
    return const <MasterLeague>[];
  }
});
