import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/master_leagues_repository_firebase.dart';
import '../data/organizer_feed_firebase.dart';
import '../domain/master_league.dart';
import 'master_league_entitlement_service.dart';
import 'master_league_payment_service.dart';

final masterLeaguesRepositoryProvider =
    Provider<MasterLeaguesRepositoryFirebase>((ref) {
  return MasterLeaguesRepositoryFirebase();
});

final organizerFeedFirebaseProvider = Provider<OrganizerFeedFirebase>((ref) {
  return OrganizerFeedFirebase();
});

final masterLeaguePaymentServiceProvider =
    Provider<FlutterwaveMasterLeaguePaymentService>((ref) {
  return FlutterwaveMasterLeaguePaymentService();
});

final masterLeagueEntitlementServiceProvider =
    Provider<MasterLeagueEntitlementService>((ref) {
  return MasterLeagueEntitlementService();
});

final myMasterLeaguesProvider = StreamProvider.autoDispose<List<MasterLeague>>((
  ref,
) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchMyMasterLeagues();
});

final createdMasterLeaguesProvider =
    StreamProvider.autoDispose<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchCreatedMasterLeagues();
});

final joinedMasterLeaguesProvider =
    StreamProvider.autoDispose<List<MasterLeague>>((ref) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchJoinedMasterLeagues();
});

final featuredOrganizerWorkspacesProvider =
    FutureProvider.autoDispose<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.discoverFeaturedOrganizers(limit: 8);
});

final verifiedOrganizerWorkspacesProvider =
    FutureProvider.autoDispose<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.discoverVerifiedOrganizers(limit: 12);
});

final recentActiveOrganizerWorkspacesProvider =
    FutureProvider.autoDispose<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.discoverRecentActiveOrganizers(limit: 12);
});

final allOrganizerWorkspacesProvider =
    FutureProvider.autoDispose<List<MasterLeague>>((ref) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.discoverAllOrganizers(limit: 20);
});
