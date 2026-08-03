// lib/features/master_leagues/logic/master_league_entitlement_service.dart

// off 'ownerId' first in isMasterLeagueOwner()).
//
// All other logic (activation, workspace/competition counting, Google
// Play vs Flutterwave routing) is UNCHANGED.
//
// ─────────────────────────────────────────────────────────────────────────
// ROOT CAUSE HISTORY (read this before touching plan-resolution again):
//
// The Firestore `master_leagues` `create`/`update` rules now accept a
// paid-plan write via TWO independent paths (see firestore.rules):
//
//   1. Firebase Auth CUSTOM CLAIMS on the ID token
//      (request.auth.token.organizerPro / organizerProPlan) — set
//      server-side by the activation worker that ONLY the Flutterwave
//      path calls (see activateAfterPayment() below).
//
//   2. The Firestore `/users/{uid}` PROFILE document
//      (activePlanId / planExpiresAtMs) — written by
//      UserProfileRepository.activatePlanSubscription() for BOTH
//      payment providers, including Google Play Billing.
//
// Google Play Billing purchases (Android's default payment route)
// NEVER go through the worker, so they NEVER get the custom claims.
// The profile document is therefore the ONLY reliable, provider-agnostic
// source of truth for "does this user actually have an active paid
// plan right now" — which is exactly why the Firestore rule was given
// a profile-based branch.
//
// CONSEQUENCE FOR THIS FILE: [getProfilePlanStrict] — not
// [getClaimsPlanStrict] — is the resolver that must be used to decide
// the `plan` value written to a new/existing `master_leagues` document
// whenever no NEW payment is being made. Using the claims-only
// resolver as the sole source will make every Google Play purchaser
// look like they have no active plan (their token never carries the
// claim) and force them back into the payment flow for a plan they
// already own. [getClaimsPlanStrict] is kept below only as a
// diagnostic/fallback helper — never call it in place of
// [getProfilePlanStrict] for the primary write-plan decision.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/backend_config.dart';
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

  bool get isExpiringSoon =>
      active && plan != null && !plan!.isFree && daysRemaining <= 7;

  bool canCreateWorkspace(int currentCount) {
    if (!active || plan == null) return false;
    return plan!.canCreateWorkspace(currentCount);
  }

  bool canCreateCompetition(int currentCount) {
    if (!active || plan == null) return false;
    return plan!.canCreateCompetition(currentCount);
  }

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

  /// Google Play Billing purchases must NEVER be routed through
  /// [_activateUri] — that endpoint only accepts Flutterwave receipts
  /// and returns "unsupported provider" for anything else.
  bool _isGooglePlayProvider(String provider) =>
      provider.trim().toLowerCase() == 'google_play_billing';

  /// Every signed-in user is implicitly entitled to the free Basic plan.
  OrganizerProEntitlement _implicitBasicEntitlement() {
    return const OrganizerProEntitlement(
      active: true,
      plan: MasterLeaguePlan.basic,
      duration: PlanDuration.threeMonths,
      expiryMs: 0,
      daysRemaining: 999,
    );
  }

  // ── Read from profile ─────────────────────────────────────────────────────

  Future<OrganizerProEntitlement> _readFromProfile({
    bool forceRefresh = false,
  }) async {
    final uid = _uidOrThrow();

    UserProfile? profile;
    try {
      if (forceRefresh) {
        profile = await _profileRepo.fetchByUserId(uid);
      } else {
        profile = await _profileRepo.fetchByUserIdForBootstrap(uid);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeagueEntitlementService] _readFromProfile '
          'fetch error (will try claims): $e',
        );
      }
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
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

  // ── Read from Firebase ID token claims ───────────────────────────────────
  //
  // DIAGNOSTIC / SECONDARY USE ONLY. This reflects Firebase Auth custom
  // claims, which are set ONLY by the Flutterwave activation worker —
  // Google Play Billing purchases never populate them (see the
  // file-header comment). Do not use this as the sole/primary source
  // for deciding what plan to write to a new master_leagues document;
  // use [getProfilePlanStrict] for that.
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

      final planRaw = claims['organizerProPlan'];
      final plan = (planRaw is String)
          ? MasterLeaguePlan.tryFromString(planRaw)
          : null;

      final durationRaw = claims['organizerProDuration'];
      final duration = (durationRaw is String &&
              durationRaw.trim().isNotEmpty)
          ? PlanDuration.fromString(durationRaw)
          : (plan == MasterLeaguePlan.basic
              ? PlanDuration.threeMonths
              : null);

      if (plan == null) {
        return const OrganizerProEntitlement(
          active: false,
          plan: null,
          duration: null,
          expiryMs: 0,
          daysRemaining: 0,
        );
      }

      if (!plan.isFree && expiryMs > 0 && expiryMs <= nowMs) {
        return const OrganizerProEntitlement(
          active: false,
          plan: null,
          duration: null,
          expiryMs: 0,
          daysRemaining: 0,
        );
      }

      final days = plan.isFree
          ? 999
          : (expiryMs > nowMs
              ? ((expiryMs - nowMs) / (1000 * 60 * 60 * 24))
                  .ceil()
              : 0);

      return OrganizerProEntitlement(
        active: true,
        plan: plan,
        duration: duration,
        expiryMs: plan.isFree ? 0 : expiryMs,
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

  // ── Public entitlement read ───────────────────────────────────────────────

  /// Returns the user's current entitlement, for DISPLAY / UI-gating
  /// purposes (e.g. "should I show the payment button").
  ///
  /// Priority order:
  ///   1. Firestore profile (planExpiresAtMs / activePlanId)
  ///   2. Firebase ID token custom claims (organizerPro)
  ///   3. An implicit, active Basic entitlement — every signed-in user
  ///      can always create their free workspace without paying.
  ///
  /// IMPORTANT: this method is intentionally lenient/fallback-friendly
  /// for display purposes. For deciding the `plan` value WRITTEN to a
  /// new `master_leagues` document, use [getProfilePlanStrict] — see
  /// the file-header comment for why the profile (not claims) is the
  /// correct, provider-agnostic source of truth.
  Future<OrganizerProEntitlement> getEntitlement({
    bool forceRefresh = false,
  }) async {
    try {
      _uidOrThrow();
    } catch (_) {
      return const OrganizerProEntitlement(
        active: false,
        plan: null,
        duration: null,
        expiryMs: 0,
        daysRemaining: 0,
      );
    }

    final fromProfile =
        await _readFromProfile(forceRefresh: forceRefresh);
    if (fromProfile.active) return fromProfile;

    final fromClaims = await _readFromClaims();
    if (fromClaims.active) return fromClaims;

    return _implicitBasicEntitlement();
  }

  /// ── THE authoritative resolver for writing `plan` on a new or
  /// existing Pro/Elite `master_leagues` document when NO new payment
  /// is being made for this action. ──
  ///
  /// Reads exclusively from the Firestore `/users/{uid}` document —
  /// no custom-claims fallback, no implicit-Basic fallback — so the
  /// returned value is GUARANTEED to equal `profile.data.activePlanId`
  /// (or be `null` if that document/field genuinely has no active paid
  /// plan right now).
  ///
  /// The Firestore security rules' `profilePlanActiveCreate()` /
  /// `profilePlanActive()` gates (see firestore.rules) check this same
  /// document directly, so this is the value guaranteed to match what
  /// the rule evaluates — for BOTH Flutterwave and Google Play Billing
  /// purchasers, since `UserProfileRepository.activatePlanSubscription()`
  /// writes this document for both providers.
  ///
  /// Do NOT replace calls to this method with [getClaimsPlanStrict] —
  /// Google Play purchasers never carry the custom claims that method
  /// reads, so doing so makes every Google Play Pro/Elite user look
  /// unentitled and forces them back into the payment flow for a plan
  /// they already own. This exact regression has happened before —
  /// see the file-header comment.
  ///
  /// Throws [MasterLeagueEntitlementException] if the profile document
  /// cannot be read at all (rather than silently guessing), so the
  /// caller can show a clear "please try again" message instead of
  /// writing a doomed-to-be-rejected value.
  Future<MasterLeaguePlan?> getProfilePlanStrict({
    bool forceRefresh = true,
  }) async {
    final uid = _uidOrThrow();

    UserProfile? profile;
    try {
      profile = forceRefresh
          ? await _profileRepo.fetchByUserId(uid)
          : await _profileRepo.fetchByUserIdForBootstrap(uid);
    } catch (e) {
      throw MasterLeagueEntitlementException(
        "We couldn't confirm your active plan. Please check your "
        'connection and try again. (${e.toString()})',
      );
    }

    if (profile == null) return null;

    final subscription = profile.planSubscription;
    if (subscription == null || !subscription.isActive) return null;
    if (subscription.plan.isFree) return null;

    return subscription.plan;
  }

  /// Claims-only resolver. Force-refreshes the ID token and reads ONLY
  /// the Firebase Auth custom claims (`organizerPro` / `organizerProPlan`).
  ///
  /// DIAGNOSTIC / FALLBACK USE ONLY — kept for callers that specifically
  /// need to know "does this user's current ID token carry the
  /// claims-based entitlement" (e.g. debugging a Flutterwave activation
  /// that hasn't propagated yet). This will always return `null` for
  /// Google Play Billing purchasers, since that path never sets these
  /// claims (see [activateAfterPayment]). Never use this as the sole
  /// source for deciding what plan to write — use
  /// [getProfilePlanStrict] for that.
  Future<MasterLeaguePlan?> getClaimsPlanStrict({
    bool forceRefresh = true,
  }) async {
    _uidOrThrow();

    final ent = await _readFromClaims();
    if (!ent.active || ent.plan == null) return null;
    if (ent.plan == MasterLeaguePlan.basic) return null;
    return ent.plan;
  }

  Stream<bool> watchUnlocked() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream.value(false);

    return _profileRepo.watchByUserId(uid).map((profile) {
      if (profile == null) return true;

      final subscription = profile.planSubscription;
      if (subscription != null && subscription.isActive) return true;

      return true;
    }).handleError((_) {
      return true;
    });
  }

  Future<bool> isUnlocked({bool forceRefresh = false}) async {
    final ent =
        await getEntitlement(forceRefresh: forceRefresh);
    return ent.active;
  }

  Future<MasterLeaguePlan?> getActivePlan(
      {bool forceRefresh = false}) async {
    final ent =
        await getEntitlement(forceRefresh: forceRefresh);
    return ent.plan;
  }

  Future<PlanDuration?> getActiveDuration(
      {bool forceRefresh = false}) async {
    final ent =
        await getEntitlement(forceRefresh: forceRefresh);
    return ent.duration;
  }

  // ── Workspace / competition counts ────────────────────────────────────────

  Future<int> countOwnedWorkspaces() async {
    final uid = _uidOrThrow();

    try {
      final snap = await _firestore
          .collection('master_leagues')
          .where('ownerId', isEqualTo: uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      return snap.docs.length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeagueEntitlementService] countOwnedWorkspaces '
          'error: $e',
        );
      }
      return 0;
    }
  }

  Future<int> countCompetitionsInWorkspace(
      String masterLeagueId) async {
    _uidOrThrow();

    try {
      final snap = await _firestore
          .collection('leagues')
          .where(
            'masterLeagueId',
            isEqualTo: masterLeagueId.trim(),
          )
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      return snap.docs.length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeagueEntitlementService] '
          'countCompetitionsInWorkspace error: $e',
        );
      }
      return 0;
    }
  }

  Future<bool> canCreateWorkspace() async {
    final ent = await getEntitlement();
    if (!ent.active || ent.plan == null) return false;
    final count = await countOwnedWorkspaces();
    return ent.plan!.canCreateWorkspace(count);
  }

  Future<bool> canCreateCompetitionInWorkspace(
      String masterLeagueId) async {
    final ent = await getEntitlement();
    if (!ent.active || ent.plan == null) return false;
    final count =
        await countCompetitionsInWorkspace(masterLeagueId);
    return ent.plan!.canCreateCompetition(count);
  }

  // ── Activation ────────────────────────────────────────────────────────────

  Uri _activateUri() {
    final fromConfig = BackendConfig.organizerProActivateUrl();
    if (fromConfig != null) return fromConfig;

    throw const MasterLeagueEntitlementException(
      'Organizer Pro activation service is not configured. '
      'Please contact support.',
    );
  }

  Future<Map<String, dynamic>> _postJson({
    required Uri uri,
    required String idToken,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $idToken',
      );
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.json.mimeType,
      );
      req.add(utf8.encode(jsonEncode(body)));

      final res = await req.close().timeout(timeout);
      final raw = await res.transform(utf8.decoder).join();

      Map<String, dynamic> parsed = <String, dynamic>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        parsed = <String, dynamic>{'raw': raw};
      }

      if (kDebugMode) {
        debugPrint(
          '[OrganizerProActivate] POST $uri '
          '-> ${res.statusCode} $raw',
        );
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (parsed['error'] as String?)?.trim();
        throw MasterLeagueEntitlementException(
          msg?.isNotEmpty == true
              ? msg!
              : 'Activation failed (${res.statusCode}). '
                  'Please try again.',
        );
      }

      return parsed;
    } on MasterLeagueEntitlementException {
      rethrow;
    } on SocketException {
      throw const MasterLeagueEntitlementException(
        'Your network appears to be offline. '
        'Please check your connection and try again.',
      );
    } on HandshakeException {
      throw const MasterLeagueEntitlementException(
        'Secure connection failed. Please try again.',
      );
    } on TimeoutException {
      throw const MasterLeagueEntitlementException(
        "We couldn't activate Organizer Pro right now. "
        'Please try again.',
      );
    } catch (_) {
      throw const MasterLeagueEntitlementException(
        "We couldn't activate Organizer Pro right now. "
        'Please try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> activateAfterPayment({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String receiptId,
    required String provider,
  }) async {
    _uidOrThrow();

    if (plan.requiresPayment && receiptId.trim().isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Missing receipt ID.',
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const MasterLeagueEntitlementException(
        'Please sign in and try again.',
      );
    }

    // ── Free plan: no payment verification needed ─────────────────────────
    if (plan.isFree) {
      await _profileRepo.activatePlanSubscription(
        plan: plan,
        duration: duration,
        receiptId: receiptId,
        provider: provider,
      );
      return;
    }

    // ── Google Play Billing: already verified by Play SDK ─────────────────
    //
    // NOTE: this path writes ONLY to the Firestore profile — it does
    // NOT call the activation worker, so it never sets the
    // organizerPro/organizerProPlan custom claims. This is expected
    // and fine: the Firestore rules' profile-based branch
    // (profilePlanActiveCreate / profilePlanActive) authorizes
    // master_leagues writes directly off this same profile document,
    // and [getProfilePlanStrict] is what callers must use to resolve
    // the plan to write. Do not "fix" this by trying to route Google
    // Play purchases through [_activateUri] — that endpoint only
    // accepts Flutterwave receipts.
    if (_isGooglePlayProvider(provider)) {
      await _profileRepo.activatePlanSubscription(
        plan: plan,
        duration: duration,
        receiptId: receiptId,
        provider: provider,
      );

      try {
        await _auth.currentUser?.getIdToken(true);
      } catch (_) {}

      return;
    }

    // ── Flutterwave / web: verify with remote worker ──────────────────────
    final idToken = await user.getIdToken(true);
    final safeIdToken = (idToken ?? '').trim();
    if (safeIdToken.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Please sign in again and try once more.',
      );
    }

    final parsed = await _postJson(
      uri: _activateUri(),
      idToken: safeIdToken,
      body: <String, dynamic>{
        'plan': plan.id,
        'duration': duration.id,
        'provider': provider,
        'receiptId': receiptId,
      },
    );

    final success = parsed['success'] == true;
    if (!success) {
      final msg = (parsed['error'] as String?)?.trim();
      throw MasterLeagueEntitlementException(
        msg?.isNotEmpty == true
            ? msg!
            : 'Organizer Pro activation failed.',
      );
    }

    final workerPlan =
        (parsed['plan'] as String? ?? '').trim().toLowerCase();
    final workerDuration =
        (parsed['duration'] as String? ?? '').trim().toLowerCase();

    if (workerPlan != plan.id) {
      throw const MasterLeagueEntitlementException(
        'Activated plan does not match the selected plan.',
      );
    }

    if (workerDuration != duration.id) {
      throw const MasterLeagueEntitlementException(
        'Activated duration does not match the selected duration.',
      );
    }

    try {
      await _profileRepo.activatePlanSubscription(
        plan: plan,
        duration: duration,
        receiptId: receiptId,
        provider: provider,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeagueEntitlementService] activateAfterPayment: '
          'best-effort local profile sync failed after successful '
          'server-side activation (ignored): $e',
        );
      }
    }

    try {
      await _auth.currentUser?.getIdToken(true);
    } catch (_) {}
  }

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
