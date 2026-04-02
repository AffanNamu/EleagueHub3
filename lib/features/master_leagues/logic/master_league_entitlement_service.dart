import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../domain/master_league_plan.dart';

class MasterLeagueEntitlementException implements Exception {
  final String message;
  const MasterLeagueEntitlementException(this.message);

  @override
  String toString() => message;
}

class OrganizerProEntitlement {
  final bool active;
  final MasterLeaguePlan? plan;
  final PlanDuration? duration;
  final int expiryMs;
  final int daysRemaining;

  const OrganizerProEntitlement({
    required this.active,
    required this.plan,
    required this.duration,
    required this.expiryMs,
    required this.daysRemaining,
  });

  bool get isExpiringSoon => active && plan != null && !plan!.isFree && daysRemaining <= 7;

  /// Check if user can create another working space given current count.
  bool canCreateWorkspace(int currentCount) {
    if (!active || plan == null) return false;
    return plan!.canCreateWorkspace(currentCount);
  }

  /// Check if user can create another competition given current count.
  bool canCreateCompetition(int currentCount) {
    if (!active || plan == null) return false;
    return plan!.canCreateCompetition(currentCount);
  }

  /// Whether payment button should show for workspace creation.
  bool shouldShowPaymentForWorkspace(int currentCount) {
    if (!active || plan == null) return true;
    return plan!.shouldShowPaymentForWorkspace(currentCount);
  }
}

class MasterLeagueEntitlementService {
  MasterLeagueEntitlementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileRepository? profileRepo,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileRepo = profileRepo ?? UserProfileRepository();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileRepository _profileRepo;

  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Please sign in and try again.',
      );
    }
    return uid;
  }

  /// Read entitlement from user profile doc (source of truth).
  Future<OrganizerProEntitlement> _readFromProfile({
    bool forceRefresh = false,
  }) async {
    final uid = _uidOrThrow();

    UserProfile? profile;
    if (forceRefresh) {
      profile = await _profileRepo.fetchByUserId(uid);
    } else {
      profile = await _profileRepo.fetchByUserIdForBootstrap(uid);
    }

    if (profile == null) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
    }

    final subscription = profile.planSubscription;
    if (subscription == null || !subscription.isActive) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
    }

    return OrganizerProEntitlement(
      active: true,
      plan: subscription.plan,
      duration: subscription.duration,
      expiryMs: subscription.expiresAtMs,
      daysRemaining: subscription.daysRemaining,
    );
  }

  /// Also check custom claims as fallback (for backward compat with worker).
  Future<OrganizerProEntitlement> _readFromClaims() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
    }

    try {
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? <String, dynamic>{};

      final active = claims['organizerPro'] == true;
      if (!active) {
        return const OrganizerProEntitlement(
          active: false,
          plan: null,
          duration: null,
          expiryMs: 0,
          daysRemaining: 0,
        );
      }

      int expiryMs = 0;
      final rawExpiry = claims['organizerProExpiryMs'];
      if (rawExpiry is int) expiryMs = rawExpiry;
      if (rawExpiry is num) expiryMs = rawExpiry.toInt();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (expiryMs > 0 && expiryMs <= nowMs) {
        return const OrganizerProEntitlement(
          active: false,
          plan: null,
          duration: null,
          expiryMs: 0,
          daysRemaining: 0,
        );
      }

      final planRaw = claims['organizerProPlan'];
      final plan = (planRaw is String)
          ? MasterLeaguePlan.tryFromString(planRaw)
          : null;

      final durationRaw = claims['organizerProDuration'];
      final duration = (durationRaw is String)
          ? PlanDuration.fromString(durationRaw)
          : null;

      final days = expiryMs > nowMs
          ? ((expiryMs - nowMs) / (1000 * 60 * 60 * 24)).ceil()
          : 0;

      return OrganizerProEntitlement(
        active: plan != null,
        plan: plan,
        duration: duration,
        expiryMs: expiryMs,
        daysRemaining: days,
      );
    } catch (_) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
    }
  }

  /// Get the current entitlement. Checks profile first, falls back to claims.
  Future<OrganizerProEntitlement> getEntitlement({
    bool forceRefresh = false,
  }) async {
    _uidOrThrow();

    final fromProfile = await _readFromProfile(forceRefresh: forceRefresh);
    if (fromProfile.active) return fromProfile;

    // Fallback: check custom claims (backward compat)
    final fromClaims = await _readFromClaims();
    return fromClaims;
  }

  Stream<bool> watchUnlocked() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream.value(false);

    return _profileRepo.watchHasActivePlan(uid);
  }

  Future<bool> isUnlocked({bool forceRefresh = false}) async {
    final ent = await getEntitlement(forceRefresh: forceRefresh);
    return ent.active;
  }

  Future<MasterLeaguePlan?> getActivePlan({bool forceRefresh = false}) async {
    final ent = await getEntitlement(forceRefresh: forceRefresh);
    return ent.plan;
  }

  Future<PlanDuration?> getActiveDuration({bool forceRefresh = false}) async {
    final ent = await getEntitlement(forceRefresh: forceRefresh);
    return ent.duration;
  }

  /// Count how many master leagues (working spaces) the user currently owns.
  Future<int> countOwnedWorkspaces() async {
    final uid = _uidOrThrow();

    final snap = await _firestore
        .collection('master_leagues')
        .where('ownerUid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    return snap.docs.length;
  }

  /// Count competitions inside a specific master league.
  Future<int> countCompetitionsInWorkspace(String masterLeagueId) async {
    _uidOrThrow();

    final snap = await _firestore
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    return snap.docs.length;
  }

  /// Check if user can create another working space.
  Future<bool> canCreateWorkspace() async {
    final ent = await getEntitlement();
    if (!ent.active || ent.plan == null) return false;

    final count = await countOwnedWorkspaces();
    return ent.plan!.canCreateWorkspace(count);
  }

  /// Check if user can create another competition in a workspace.
  Future<bool> canCreateCompetitionInWorkspace(String masterLeagueId) async {
    final ent = await getEntitlement();
    if (!ent.active || ent.plan == null) return false;

    final count = await countCompetitionsInWorkspace(masterLeagueId);
    return ent.plan!.canCreateCompetition(count);
  }

  /// Activate a plan after successful payment by writing to user profile.
  Future<void> activateAfterPayment({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String receiptId,
    required String provider,
  }) async {
    _uidOrThrow();

    if (plan.requiresPayment && receiptId.trim().isEmpty) {
      throw const MasterLeagueEntitlementException('Missing receipt ID.');
    }

    await _profileRepo.activatePlanSubscription(
      plan: plan,
      duration: duration,
      receiptId: receiptId,
      provider: provider,
    );
  }

  /// Activate the free basic plan (no payment needed).
  Future<void> activateBasicFreePlan() async {
    _uidOrThrow();

    await _profileRepo.activatePlanSubscription(
      plan: MasterLeaguePlan.basic,
      duration: PlanDuration.threeMonths,
      receiptId: 'free_basic',
      provider: 'free',
    );
  }
}
