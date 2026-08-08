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

  // FIXED: this previously matched ONLY the literal string
  // 'google_play_billing'. MasterLeaguesRepositoryFirebase and
  // firestore.rules (see validProvider()) both also treat plain
  // 'google_play' as a valid Google Play Billing provider value. When
  // the payment SDK reported 'google_play' instead of
  // 'google_play_billing', activateAfterPayment() below fell through
  // to the Flutterwave/web worker branch instead of writing the
  // Firestore profile directly -- so users/{uid}.activePlanId never got
  // set for that purchase, and every subsequent master_leagues create
  // was rejected by firestore.rules' profileHasActivePlan() with
  // permission-denied, even though the in-app purchase itself had
  // succeeded. This is the root cause of "user has a plan but can't
  // create a workspace on mobile" while the web app (Flutterwave-only)
  // was unaffected.
  bool _isGooglePlayProvider(String provider) {
    final p = provider.trim().toLowerCase();
    return p == 'google_play_billing' || p == 'google_play';
  }

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

  // ── Public entitlement read
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

  /// ── THE authoritative resolver for writing `plan` on a new or old
  /// master league. Reads the EXACT fields Firestore's
  /// `profileHasActivePlan()` rule checks, and reads them with a
  /// forced SERVER round-trip -- never the local cache.
  ///
  /// FIXED (mobile-only regression #1): this previously delegated to
  /// `_profileRepo.fetchByUserId(uid)`. On mobile, firebase_firestore
  /// has offline persistence ON by default, and that repository call
  /// does not guarantee a true server round-trip even when
  /// "forceRefresh" is requested. That let the UI (via getEntitlement,
  /// which uses the same repository call) and this resolver both agree
  /// -- from a stale locally-cached profile -- that the user had an
  /// active Pro/Elite plan, so the app skipped payment and went
  /// straight to `repo.create()`. But the ACTUAL server document (the
  /// one Firestore's `profileHasActivePlan()` rule reads live during
  /// evaluation) disagreed, so the write came back permission-denied.
  /// The web app never hit this because its Firestore client has no
  /// persistent cache and always reads fresh from the server.
  ///
  /// This version reads the users/{uid} document directly, with an
  /// explicit `Source.server`, bypassing the repository entirely for
  /// this specific security-critical decision.
  Future<MasterLeaguePlan?> getProfilePlanStrict({
    bool forceRefresh = true,
  }) async {
    final uid = _uidOrThrow();

    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw MasterLeagueEntitlementException(
        "We couldn't confirm your active plan. Please check your "
        'connection and try again. (${e.toString()})',
      );
    }

    if (!snap.exists) return null;
    final data = snap.data() ?? <String, dynamic>{};

    final activePlanId = (data['activePlanId'] as String? ?? '').trim();
    if (activePlanId != 'pro' && activePlanId != 'elite') return null;

    final rawExpiry = data['planExpiresAtMs'];
    int expiresAtMs = 0;
    if (rawExpiry is int) expiresAtMs = rawExpiry;
    if (rawExpiry is num) expiresAtMs = rawExpiry.toInt();
    if (rawExpiry is Timestamp) {
      expiresAtMs = rawExpiry.millisecondsSinceEpoch;
    }

    if (expiresAtMs <= DateTime.now().millisecondsSinceEpoch) return null;

    return MasterLeaguePlan.tryFromString(activePlanId);
  }

  /// Retries [getProfilePlanStrict] briefly, returning as soon as it
  /// resolves to an active Pro/Elite plan. Use this instead of a
  /// single-shot check anywhere the result gates a write that
  /// firestore.rules' `profileHasActivePlan()` will independently
  /// re-check (e.g. right before creating a master league) -- including
  /// immediately after a payment is activated, where there can be a
  /// short window between the profile write being acknowledged locally
  /// and being visible to a fresh Source.server read (for example, if
  /// `waitForPendingWrites()` inside [activateAfterPayment] times out
  /// and is swallowed).
  ///
  /// Returns null if, after all attempts, the profile still shows no
  /// active Pro/Elite plan (caller should treat this as "a payment is
  /// genuinely required" rather than retrying indefinitely). Throws
  /// [MasterLeagueEntitlementException] only if every attempt failed
  /// due to a connectivity/read error (as opposed to a clean "no active
  /// plan" read).
  Future<MasterLeaguePlan?> getProfilePlanStrictWithRetry({
    int attempts = 4,
    Duration initialDelay = const Duration(milliseconds: 400),
  }) async {
    Duration delay = initialDelay;
    Object? lastError;

    for (int i = 0; i < attempts; i++) {
      try {
        final plan = await getProfilePlanStrict(forceRefresh: true);
        if (plan == MasterLeaguePlan.pro || plan == MasterLeaguePlan.elite) {
          return plan;
        }
        lastError = null;
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint(
            '[MasterLeagueEntitlementService] '
            'getProfilePlanStrictWithRetry attempt ${i + 1}/$attempts '
            'failed: $e',
          );
        }
      }

      if (i < attempts - 1) {
        await Future.delayed(delay);
        delay *= 2;
      }
    }

    if (lastError != null) {
      throw MasterLeagueEntitlementException(
        "We couldn't confirm your active plan. Please check your "
        'connection and try again. (${lastError.toString()})',
      );
    }

    return null;
  }

  /// Claims-only resolver. Force-refreshes the ID token and reads ONLY
  /// the Firebase Auth custom claims (`organizerPro` / `organizerProPlan`).
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
    // NEW: the Google Play purchase token, required for the worker to
    // verify the purchase against the Play Developer API. Falls back to
    // `receiptId` if not supplied separately, since some callers still
    // only pass a single receipt-like value.
    String purchaseToken = '',
  }) async {
    _uidOrThrow();

    if (plan.requiresPayment &&
        receiptId.trim().isEmpty &&
        purchaseToken.trim().isEmpty) {
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

      try {
        await _firestore
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 15));
      } catch (_) {}

      return;
    }

    // ── FIXED: Google Play Billing now activates through the SAME
    // Cloudflare Worker as Flutterwave, using the SAME
    // organizerPro/organizerProPlan custom claims — instead of writing
    // the Firestore profile directly and relying on firestore.rules'
    // profileHasActivePlan() fallback to authorize master_leagues
    // writes. That profile-based fallback was never confirmed to
    // actually work in production (web has only ever exercised the
    // claims branch), and it's the branch that's been failing.
    //
    // The worker independently verifies the purchase against the
    // Google Play Developer API (purchases.subscriptionsv2.get) before
    // granting anything, so this is not a weaker guarantee than the
    // old direct write — if anything it's stronger, since Google's own
    // subscriptionState/expiryTime become the source of truth instead
    // of a client-computed expiry estimate.
    if (_isGooglePlayProvider(provider)) {
      final idToken = await user.getIdToken(true);
      final safeIdToken = (idToken ?? '').trim();
      if (safeIdToken.isEmpty) {
        throw const MasterLeagueEntitlementException(
          'Please sign in again and try once more.',
        );
      }

      final safePurchaseToken = purchaseToken.trim().isNotEmpty
          ? purchaseToken.trim()
          : receiptId.trim();
      if (safePurchaseToken.isEmpty) {
        throw const MasterLeagueEntitlementException(
          'Missing Google Play purchase token. Please try again.',
        );
      }

      final parsed = await _postJson(
        uri: _activateUri(),
        idToken: safeIdToken,
        body: <String, dynamic>{
          'plan': plan.id,
          'duration': duration.id,
          'provider': 'google_play_billing',
          'purchaseToken': safePurchaseToken,
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

      // Best-effort local profile mirror so the UI ("Active plan: Pro")
      // reflects the change immediately without waiting on a token
      // refresh round-trip. The worker has already written the
      // authoritative copy via its own service-account credentials
      // (which bypass rules), so this is purely a UX nicety now — if
      // it fails, master_leagues creation still works via the custom
      // claim set above.
      try {
        await _profileRepo.activatePlanSubscription(
          plan: plan,
          duration: duration,
          receiptId: safePurchaseToken,
          provider: 'google_play_billing',
        );
        await _firestore
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[MasterLeagueEntitlementService] activateAfterPayment: '
            'best-effort local profile sync failed after successful '
            'server-side Google Play activation (ignored, claims are '
            'already set): $e',
          );
        }
      }

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
      await _firestore
          .waitForPendingWrites()
          .timeout(const Duration(seconds: 15));
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

    try {
      await _firestore
          .waitForPendingWrites()
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
