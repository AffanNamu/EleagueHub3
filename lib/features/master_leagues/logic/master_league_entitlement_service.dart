// lib/features/master_leagues/logic/master_league_entitlement_service.dart
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
  /// FIXED (mobile-only regression): this previously delegated to
  /// `_profileRepo.fetchByUserId(uid)`. On mobile, firebase_firestore
  /// has offline persistence ON by default, and that repository call
  /// does not guarantee a true server round-trip even when
  /// "forceRefresh" is requested. That let the UI (via getEntitlement,
  /// which uses the same repository call) and this resolver both agree
  /// -- from a stale locally-cached profile -- that the user had an
  /// active Pro/Elite plan, so the app skipped payment and went
  /// straight to `repo.create()`. But the ACTUAL server document (the
  /// one Firestore's `profileHasActivePlan()` rule reads live during
  /// evaluation) disagreed, so the write came back permission-denied:
  /// "You don't have access to this Master League...". The web app
  /// never hit this because its Firestore client has no persistent
  /// cache and always reads fresh from the server.
  ///
  /// This version reads the users/{uid} document directly, with an
  /// explicit `Source.server`, bypassing the repository entirely for
  /// this specific security-critical decision. It can no longer
  /// disagree with what the security rule itself will see.
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