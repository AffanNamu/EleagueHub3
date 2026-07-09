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
// FIX: getEntitlement() falls back to an implicit, active Basic
// entitlement whenever neither the profile nor the claims show an
// active paid plan.
//
// ── NEW, ACTUAL ROOT-CAUSE FIX FOR THIS REVISION ───────────────────────
// THE REAL BUG (found by tracing the permission-denied reports where
// EVERY Pro/Elite user was rejected creating a workspace — first one or
// fifth one, didn't matter — while Basic/free and super admin worked):
//
// getEntitlement() has THREE possible sources, in priority order:
//   1. Firestore profile          (profile.data.activePlanId)
//   2. Firebase custom claims     (organizerPro / organizerProPlan)
//   3. Implicit Basic fallback    (added by the fix above)
//
// firestore.rules' profilePlanActiveCreate() (and the claims-based gate)
// require an EXACT match:
//
//     request.resource.data.plan == profile.data.activePlanId
//
// CreateMasterLeagueScreen._create() — for the common "I already have
// an active paid plan with room under my limit, no new payment needed"
// path — calls:
//
//     final refreshedPlan = refreshedEnt.plan ?? _selectedPlan;
//     repo.create(plan: refreshedPlan, ...)
//
// where refreshedEnt comes from getEntitlement(). The problem: ANY
// transient failure reading the Firestore profile (a timeout, a brief
// permission hiccup, Source.server being momentarily unreachable) makes
// _readFromProfile() report inactive. Google Play users NEVER get
// organizerPro custom claims set client-side (only an async RTDN
// webhook sets those, server-side) — so _readFromClaims() ALSO reports
// inactive for them. getEntitlement() then silently falls through to
// the implicit Basic entitlement (fix #1 above), and _create() happily
// writes `'plan': 'basic'` to the new master_leagues document — while
// `profile.data.activePlanId` on the user's own profile still says
// 'pro' or 'elite'. Every plan-based Firestore rule gate then fails its
// `plan == profilePlan` equality check (the write says 'basic', the
// profile says 'pro'/'elite' — they can never match), and Firestore
// rejects the write with permission-denied. This reproduces the exact
// reported symptom: it doesn't matter whether the user has 0 workspaces
// or 4 out of a 5-workspace Pro limit — a single transient profile read
// blip picks the wrong plan value for the WRITE, independent of the
// workspace count.
//
// FIX: added getProfilePlanStrict(), which reads ONLY the Firestore
// profile — no claims fallback, no implicit-Basic fallback — and is now
// the single source of truth CreateMasterLeagueScreen uses to decide
// what `plan` value to write when no new payment is required. This
// guarantees request.resource.data.plan always equals
// profile.data.activePlanId exactly, which is precisely what the
// security rules check. If the strict profile read itself fails, we
// surface that as a clear, retryable error instead of silently writing
// a mismatched 'basic' value that is guaranteed to be denied.
//
// ── ADDITIONAL FIX (earlier revision) ──────────────────────────────────
// countOwnedWorkspaces() previously filtered master_leagues by the
// `ownerUid` field, while MasterLeaguesRepositoryFirebase's
// checkMasterLeagueLimitOrThrow() and _allocateMasterLeagueIdForPlan()
// both filter by `ownerId`. Standardized on `ownerId` everywhere
// (matching the repository and the Firestore security rules, which key
// off 'ownerId' first in isMasterLeagueOwner()).
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
  /// for display purposes and MUST NOT be used to decide the `plan`
  /// value written to a new `master_leagues` document when no new
  /// payment is being made. Use [getProfilePlanStrict] for that — see
  /// the file-header comment for why: the fallback chain here can
  /// legitimately diverge from `profile.data.activePlanId`, which is
  /// exactly what the Firestore security rules compare the write
  /// against.
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

  /// ── NEW: STRICT, profile-ONLY plan resolver. ──────────────────────────
  ///
  /// Reads exclusively from the Firestore `/users/{uid}` document —
  /// no custom-claims fallback, no implicit-Basic fallback — so the
  /// returned value is GUARANTEED to equal `profile.data.activePlanId`
  /// (or be `null` if that document/field genuinely has no active paid
  /// plan right now).
  ///
  /// This is the ONLY method that should be used to decide the `plan`
  /// value written to a new `master_leagues` document whenever NO new
  /// payment is being made for that creation (i.e. the user is relying
  /// on an already-active plan with room under their workspace limit).
  /// Using anything else (in particular [getEntitlement], which can
  /// fall back to claims or an implicit Basic entitlement) risks
  /// writing a `plan` value that does not match
  /// `profile.data.activePlanId`, which the Firestore security rules'
  /// `profilePlanActiveCreate()` / `googlePlayPlanActiveCreate()` gates
  /// require to match EXACTLY — a mismatch here is denied with
  /// permission-denied regardless of workspace count.
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