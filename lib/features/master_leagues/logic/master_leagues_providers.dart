// lib/features/master_leagues/logic/master_leagues_providers.dart

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

// ── Repositories & services ───────────────────────────────────────────────

final masterLeaguesRepositoryProvider =
    Provider<MasterLeaguesRepositoryFirebase>((ref) {
  return MasterLeaguesRepositoryFirebase();
});

final organizerFeedFirebaseProvider =
    Provider<OrganizerFeedFirebase>((ref) {
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

final userProfileRepositoryProvider =
    Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

// ── Master League streams ─────────────────────────────────────────────────

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
    FutureProvider.autoDispose.family<MasterLeague?, String>(
        (ref, id) async {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.getById(id);
});

final masterLeagueFollowStateProvider =
    StreamProvider.autoDispose.family<bool, String>(
        (ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchIsFollowing(masterLeagueId);
});

final masterLeagueFollowersCountProvider =
    StreamProvider.autoDispose.family<int, String>(
        (ref, masterLeagueId) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchFollowersCount(masterLeagueId);
});

final masterLeagueCompetitionTemplatesProvider =
    StreamProvider.autoDispose
        .family<List<CompetitionTemplate>, String>((
  ref,
  masterLeagueId,
) {
  final repo = ref.watch(masterLeaguesRepositoryProvider);
  return repo.watchCompetitionTemplates(masterLeagueId);
});

// ── Entitlement / plan ────────────────────────────────────────────────────

/// The user's current entitlement (plan, expiry, limits).
final organizerEntitlementProvider =
    FutureProvider.autoDispose<OrganizerProEntitlement>(
        (ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.getEntitlement(forceRefresh: false);
});

/// The active plan or null.
final organizerProActivePlanProvider =
    FutureProvider.autoDispose<MasterLeaguePlan?>((ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.getActivePlan(forceRefresh: false);
});

/// Whether user has any active plan.
final masterLeagueUnlockedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.isUnlocked(forceRefresh: false);
});

/// Watch the user's plan subscription from their Firestore profile.
/// Uses a real-time stream so UI reacts immediately after payment.
final userPlanSubscriptionProvider =
    StreamProvider.autoDispose<UserPlanSubscription?>((ref) {
  final uid =
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(null);
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchPlanSubscription(uid);
});

/// Watch whether user has an active plan.
final userHasActivePlanProvider =
    StreamProvider.autoDispose<bool>((ref) {
  final uid =
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(false);
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchHasActivePlan(uid);
});

// ── Workspace counts ──────────────────────────────────────────────────────

/// How many workspaces the current user currently owns.
final ownedWorkspaceCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.countOwnedWorkspaces();
});

/// Whether user can create another workspace.
final canCreateWorkspaceProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);
  return svc.canCreateWorkspace();
});

// ── shouldShowWorkspacePaymentProvider ───────────────────────────────────
//
// FIXED LOGIC:
//
// The upgrade / payment button should show ONLY when the user
// genuinely needs to pay to proceed:
//
//   • No active plan at all          → show (needs to buy a plan)
//   • Basic (free) plan + at limit   → show (needs to upgrade)
//   • Pro plan + within 5 limit      → HIDE  (they already paid)
//   • Pro plan + at 5/5 limit        → show (needs Elite to get more)
//   • Elite plan                     → HIDE  (unlimited — never pay)
//
// Previously the button showed for ALL paid users regardless of
// whether they were within their plan limits, which caused Pro/Elite
// users to see a spurious "Upgrade Plan" button.

final shouldShowWorkspacePaymentProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final svc =
      ref.watch(masterLeagueEntitlementServiceProvider);

  final ent = await svc.getEntitlement(forceRefresh: false);

  // No plan at all — user must purchase.
  if (!ent.active || ent.plan == null) return true;

  final plan = ent.plan!;

  // Elite: unlimited workspaces — never show payment.
  if (plan.unlimitedMasterLeagues) return false;

  // Basic free plan: show payment only when AT the 1-workspace limit
  // so the user knows they must upgrade to create more.
  // (While under limit they can still create without paying.)
  if (plan.isFree) {
    final count = await svc.countOwnedWorkspaces();
    return count >= plan.maxMasterLeagues;
  }

  // Pro (paid): show payment only if they have reached their
  // 5-workspace ceiling and need Elite to go further.
  // While they are under the limit the button must be hidden.
  final count = await svc.countOwnedWorkspaces();
  return count >= plan.maxMasterLeagues;
});

// ── Discovery ─────────────────────────────────────────────────────────────

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

// ── Current user profile stream ───────────────────────────────────────────
//
// Used by MasterLeaguesListScreen to show the signed-in user's
// display name and verification badges in the info card header.

final currentUserProfileStreamProvider =
    StreamProvider.autoDispose<UserProfile?>((ref) {
  final uid =
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) return Stream.value(null);
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watchByUserId(uid);
});

// ── Owner profile by UID ──────────────────────────────────────────────────
//
// Fetches any user's profile once so the MasterLeagueCard can
// display the organizer's real display name and verification badge.
// Uses FutureProvider.family with autoDispose so profiles are cached
// per UID for the lifetime of the screen, then released.

final masterLeagueOwnerProfileProvider =
    FutureProvider.autoDispose.family<UserProfile?, String>(
        (ref, ownerUid) async {
  if (ownerUid.trim().isEmpty) return null;
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.fetchByUserId(ownerUid.trim());
});