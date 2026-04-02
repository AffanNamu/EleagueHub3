import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/master_leagues_repository_firebase.dart';
import '../data/organizer_feed_firebase.dart';
import '../domain/competition_template.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
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

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

final myMasterLeaguesProvider =
    StreamProvider.autoDispose<List<MasterLeague>>((ref) {
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

final masterLeagueByIdProvider =
    FutureProvider.autoDispose.family<MasterLeague?, String>((ref, id) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.getById(id);
});

final masterLeagueFollowStateProvider =
    StreamProvider.autoDispose.family<bool, String>((ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchIsFollowing(masterLeagueId);
});

final masterLeagueFollowersCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchFollowersCount(masterLeagueId);
});

final masterLeagueCompetitionTemplatesProvider =
    StreamProvider.autoDispose.family<List<CompetitionTemplate>, String>((
  ref,
  masterLeagueId,
) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchCompetitionTemplates(masterLeagueId);
});

/// The user's current entitlement (plan, expiry, limits).
final organizerEntitlementProvider =
    FutureProvider.autoDispose<OrganizerProEntitlement>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.getEntitlement(forceRefresh: false);
});

/// The active plan or null.
final organizerProActivePlanProvider =
    FutureProvider.autoDispose<MasterLeaguePlan?>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.getActivePlan(forceRefresh: false);
});

/// Whether user has any active plan.
final masterLeagueUnlockedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.isUnlocked(forceRefresh: false);
});

/// Watch the user's plan subscription from their profile.
final userPlanSubscriptionProvider =
    StreamProvider.autoDispose<UserPlanSubscription?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(null);
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchPlanSubscription(uid);
});

/// Watch whether user has an active plan.
final userHasActivePlanProvider = StreamProvider.autoDispose<bool>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(false);
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchHasActivePlan(uid);
});

/// How many workspaces the user currently owns.
final ownedWorkspaceCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.countOwnedWorkspaces();
});

/// Whether user can create another workspace.
final canCreateWorkspaceProvider = FutureProvider.autoDispose<bool>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  return entitlement.canCreateWorkspace();
});

/// Whether the payment button should show for workspace creation.
final shouldShowWorkspacePaymentProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final entitlement = ref.watch(masterLeagueEntitlementServiceProvider);
  final ent = await entitlement.getEntitlement();
  if (!ent.active || ent.plan == null) return true; // No plan = show payment
  final count = await entitlement.countOwnedWorkspaces();
  return ent.plan!.shouldShowPaymentForWorkspace(count);
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
