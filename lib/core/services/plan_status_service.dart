// lib/core/services/plan_status_service.dart
//
// SINGLE SOURCE OF TRUTH for "does this user currently have an active
// paid plan" — replaces THREE previously-divergent implementations:
//
//   1. qr_scanner_screen.dart's _loadPlanState(), which read
//      UserProfileRepository().fetchByUserId(uid).activePlan
//   2. leagues_list_screen.dart's _detectPremiumUser(), which checked
//      Firebase ID token custom claims FIRST, then fell back to raw
//      Firestore users/{uid} fields.
//   3. leagues_repository_local.dart's _isPremiumUser(), which checked
//      ONLY legacy isPremium/premiumExpiresAtMs fields and matching
//      claims — never checking activePlanId for 'pro'/'elite' at all.
//
// WHY THIS MATTERS:
//   Custom claims (organizerPro / isPremium / activePlanId on the ID
//   token) are ONLY set server-side by the Google Play RTDN webhook.
//   A Flutterwave (web) purchase NEVER sets custom claims — it only
//   writes activePlanId / planExpiresAtMs / planProvider directly onto
//   the Firestore users/{uid} document (see
//   MasterLeagueEntitlementService.activateAfterPayment). Any screen or
//   repository method that checks claims first, or that never looks at
//   activePlanId at all, can report "no active plan" for a user who
//   clearly has one — which is exactly why a paying user was told
//   they'd hit the free 3-league creation/join limit even while
//   simply joining via QR code or invite code.
//
// FIX: Always read the Firestore users/{uid} document as the
// authoritative source (same fields the Firestore security rules
// themselves validate against: activePlanId + planExpiresAtMs +
// planProvider). Custom claims are treated as a secondary signal only,
// and only used to CONFIRM (never to override) a plan Firestore
// doesn't yet show — e.g. immediately after a Google Play purchase
// before the RTDN webhook has synced Firestore.
//
// Every screen or repository method that needs to answer "is this
// user on a paid plan" should call
// PlanStatusService.instance.isPaidPlanActive(uid) instead of rolling
// its own detection logic.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PlanStatusResult {
  final bool isPaidPlanActive;
  final String planId; // 'basic' | 'pro' | 'elite'
  final int planExpiresAtMs; // 0 = no expiry (shouldn't happen for paid plans)

  const PlanStatusResult({
    required this.isPaidPlanActive,
    required this.planId,
    required this.planExpiresAtMs,
  });

  static const none = PlanStatusResult(
    isPaidPlanActive: false,
    planId: 'basic',
    planExpiresAtMs: 0,
  );
}

class PlanStatusService {
  PlanStatusService._();
  static final PlanStatusService instance = PlanStatusService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isPaidPlanId(String? raw) {
    final id = (raw ?? '').trim().toLowerCase();
    return id == 'pro' || id == 'elite';
  }

  int _asMs(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  /// Authoritative check: reads the Firestore users/{uid} document
  /// directly from the server (bypassing any stale local cache) and
  /// evaluates activePlanId + planExpiresAtMs exactly the way the
  /// Firestore security rules and MasterLeagueEntitlementService do.
  ///
  /// This is the ONLY method screens or repositories should call to
  /// decide whether to apply free-tier limits, ad gates, or paywalls.
  Future<PlanStatusResult> getStatus({
    required String uid,
    bool forceRefreshToken = false,
  }) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return PlanStatusResult.none;

    // ── Primary source: Firestore profile document ────────────────────────
    try {
      final doc = await _firestore
          .collection('users')
          .doc(trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final data = doc.data() ?? <String, dynamic>{};
      final planId = (data['activePlanId'] as String? ?? 'basic').trim();
      final expiresAtMs = _asMs(data['planExpiresAtMs']);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (_isPaidPlanId(planId) && (expiresAtMs == 0 || expiresAtMs > now)) {
        return PlanStatusResult(
          isPaidPlanActive: true,
          planId: planId.toLowerCase(),
          planExpiresAtMs: expiresAtMs,
        );
      }

      // Legacy premium-subscription flag (separate product, still
      // grants paid-tier behavior for league gating purposes).
      final isPremiumLegacy = data['isPremium'] == true;
      final premiumExpiresAtMs = _asMs(data['premiumExpiresAtMs']);
      if (isPremiumLegacy && premiumExpiresAtMs > now) {
        return PlanStatusResult(
          isPaidPlanActive: true,
          planId: planId.toLowerCase(),
          planExpiresAtMs: premiumExpiresAtMs,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlanStatusService] Firestore read failed: $e');
      }
      // Fall through to claims-based check below rather than
      // immediately reporting "no plan" on a transient network error.
    }

    // ── Secondary source: ID token custom claims ───────────────────────────
    // Only used to CATCH a just-completed Google Play purchase whose
    // RTDN webhook hasn't written Firestore yet. Never used to
    // override a Firestore doc that already loaded successfully above.
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid.trim() != trimmed) {
        return PlanStatusResult.none;
      }

      final tokenResult = await user.getIdTokenResult(forceRefreshToken);
      final claims = tokenResult.claims ?? <String, dynamic>{};

      final claimActive =
          claims['organizerPro'] == true || claims['isPremium'] == true;
      if (!claimActive) return PlanStatusResult.none;

      final claimPlanId =
          (claims['organizerProPlan'] as String? ?? 'basic').trim();
      final claimExpiresAtMs = _asMs(claims['organizerProExpiryMs']);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (_isPaidPlanId(claimPlanId) &&
          (claimExpiresAtMs == 0 || claimExpiresAtMs > now)) {
        return PlanStatusResult(
          isPaidPlanActive: true,
          planId: claimPlanId.toLowerCase(),
          planExpiresAtMs: claimExpiresAtMs,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlanStatusService] claims read failed: $e');
      }
    }

    return PlanStatusResult.none;
  }

  /// Convenience boolean-only accessor.
  Future<bool> isPaidPlanActive(String uid, {bool forceRefreshToken = false}) async {
    final result = await getStatus(uid: uid, forceRefreshToken: forceRefreshToken);
    return result.isPaidPlanActive;
  }
}
