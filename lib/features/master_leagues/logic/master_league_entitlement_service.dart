// lib/features/master_leagues/logic/master_league_entitlement_service.dart
//
// FIXED (root cause of "works only for super admin" / "free/basic users
// can't create a master league even though they've never paid"):
//
// Previously, getEntitlement() returned `active: false, plan: null`
// whenever:
//   - the user had no Firestore profile yet (brand-new sign-up), OR
//   - the profile had no plan recorded / an expired plan, AND
//   - the ID token had no organizerPro custom claims.
//
// Basic is a FREE plan — every signed-in user is entitled to it with
// zero payment required (see MasterLeaguePlan.basic.isFree == true and
// freeBasicMasterLeagueCreate() in firestore.rules, which never checks
// entitlement/claims at all, only that plan == 'basic' and the target
// masterLeagueId matches the user's slot).
//
// The problem was entirely client-side: isUnlocked() / canCreateWorkspace()
// / watchUnlocked() all funnel through getEntitlement(), and anything in
// the UI that gates "show the Create Master League option" on those
// calls was treating "no explicit active plan yet" as "locked out" —
// which only happened to be masked for the hardcoded super admin uid,
// because that uid bypasses entitlement checks entirely at the Firestore
// rules layer (isSuperAdmin()), never at the client/service layer.
//
// FIX: getEntitlement() now falls back to an implicit, active Basic
// entitlement whenever neither the profile nor the claims show an
// active paid plan. This also naturally covers a Pro/Elite subscription
// that has expired: the user degrades to Basic instead of being fully
// locked out, matching normal SaaS behavior ("free or basic plan to
// create the working space").
//
// watchUnlocked() is updated the same way, since it previously bypassed
// getEntitlement() entirely and read UserProfile.hasPlanActive directly,
// which had the identical gap for brand-new / planless users.
//
// All other logic (activation, workspace/competition counting, Google
// Play vs Flutterwave routing) is UNCHANGED.

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

  /// ── NEW: every signed-in user is implicitly entitled to the free
  ///        Basic plan (1 workspace / up to 3 competitions), with zero
  ///        payment required. This is returned whenever neither the
  ///        Firestore profile nor the ID token claims show an active
  ///        paid (Pro/Elite) plan — covering brand-new users who have
  ///        never purchased anything, as well as users whose paid plan
  ///        has expired (they degrade to Basic instead of being locked
  ///        out entirely).
  ///
  ///        This mirrors freeBasicMasterLeagueCreate() in firestore.rules,
  ///        which likewise never requires any payment/claims for the
  ///        Basic plan — only that the target masterLeagueId matches the
  ///        user's deterministic ml_{uid}_1 slot.
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
      // Network / permission errors — fall through to claims fallback.
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

  /// Returns the user's current entitlement.
  ///
  /// Priority order:
  ///   1. Firestore profile (planExpiresAtMs / activePlanId)
  ///   2. Firebase ID token custom claims (organizerPro)
  ///   3. FIXED: an implicit, active Basic entitlement — every signed-in
  ///      user can always create their free workspace without paying,
  ///      so we never report "inactive / locked out" just because no
  ///      paid plan has ever been purchased (or a previous paid plan
  ///      has expired).
  ///
  /// Never throws — returns the implicit Basic entitlement (or, if the
  /// user isn't signed in at all, an inactive entitlement) on any error
  /// so that the UI degrades gracefully instead of showing a crash.
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

    // FIXED: neither the profile nor the claims show an active paid
    // plan — this is either a brand-new user who has never purchased
    // anything, or a user whose Pro/Elite plan has expired. Either way,
    // they are still entitled to the free Basic plan with no payment
    // required, so report them as active on Basic instead of locked out.
    return _implicitBasicEntitlement();
  }

  /// FIXED: previously watched UserProfile.hasPlanActive directly, which
  /// mirrored the exact same gap as getEntitlement() used to have — a
  /// brand-new user with no profile doc (or a profile with no plan
  /// recorded yet) streamed `false` forever, which any "Create Master
  /// League" UI gated on this stream would read as "locked out", even
  /// though Basic is free and always available. Now streams the same
  /// implicit-Basic-fallback semantics as getEntitlement().
  Stream<bool> watchUnlocked() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream.value(false);

    return _profileRepo.watchByUserId(uid).map((profile) {
      // No profile yet (brand-new user) -> implicit Basic -> unlocked.
      if (profile == null) return true;

      final subscription = profile.planSubscription;
      if (subscription != null && subscription.isActive) return true;

      // No active plan recorded on the profile (or it expired) ->
      // implicit Basic -> still unlocked, never locked out.
      return true;
    }).handleError((_) {
      // Stream error (e.g. transient permission hiccup) -> still treat
      // the user as unlocked on implicit Basic rather than showing them
      // as locked out.
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
          .where('ownerUid', isEqualTo: uid)
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
      // Return 0 on error so canCreateWorkspace defaults to permissive.
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

  /// Activates the plan after a confirmed payment.
  ///
  /// Routing:
  ///   • Free plans       → write directly to Firestore (no payment).
  ///   • Google Play      → write directly to Firestore (already verified
  ///                        by the Play Billing purchase stream). This is
  ///                        the ONLY persistence path for Google Play, so
  ///                        failures here are surfaced — there is no
  ///                        server-side fallback that already wrote the
  ///                        entitlement.
  ///   • Flutterwave/web  → POST to the remote worker for server-side
  ///                        verification. The worker activates the plan
  ///                        authoritatively (custom claims + a Firestore
  ///                        write using admin/service-account credentials
  ///                        that bypass client security rules). Once that
  ///                        succeeds, the purchase is already complete.
  ///
  /// Badges are granted automatically inside
  /// [UserProfileRepository.activatePlanSubscription].
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
    // The purchase was confirmed by the Play Billing purchase stream
    // BEFORE this method is called. We only need to persist the plan
    // locally and grant the badge (done inside activatePlanSubscription).
    // Routing this through the Flutterwave worker would cause an
    // "unsupported provider" error.
    //
    // This is the sole persistence path for Google Play purchases, so
    // unlike the Flutterwave branch below, a failure here must still be
    // surfaced to the caller — there is no admin-privileged write that
    // already activated the plan elsewhere.
    if (_isGooglePlayProvider(provider)) {
      await _profileRepo.activatePlanSubscription(
        plan: plan,
        duration: duration,
        receiptId: receiptId,
        provider: provider,
      );

      // Refresh the ID token so any cloud-function custom claims
      // set by server-side RTDN are picked up immediately.
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

    // ── FIXED: the worker call above already activated the plan
    // authoritatively — it wrote Firebase custom claims AND the
    // `users/{uid}` Firestore document using admin/service-account
    // credentials, which bypass client security rules entirely. By the
    // time we get here, the purchase has already succeeded server-side.
    //
    // The client-side write below is only a "best effort" local sync —
    // kept so that badge granting (which happens inside
    // activatePlanSubscription) runs immediately instead of waiting for
    // the next profile fetch/stream update.
    //
    // ROOT CAUSE FIXED: previously, if this redundant client-side write
    // hit ANY transient Firestore error — most commonly a
    // permission-denied caused by a stale ID token right after the
    // purchase/verification round-trip — that error was thrown from
    // here and surfaced to the purchase UI as a failed purchase, even
    // though the user had already been charged and the plan was already
    // active. This is what produced "You do not have permission to
    // access this profile" immediately after a successful Pro/Elite
    // purchase. We now log and swallow errors from this best-effort
    // local sync instead of letting them abort a purchase that has
    // already succeeded; the user's profile will reflect the correct
    // plan on the next read/stream update regardless, since the
    // Firestore document was already written by the worker.
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