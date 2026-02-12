import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/remote_pricing_service.dart';

class CouponConfig {
  final String leagueId;
  final String organizerUserId;

  // Pricing snapshot (captured at purchase time or last increment)
  final String currency; // 'NGN' or 'USD'
  final double unitPrice; // raw unit price per coupon (before any threshold discount)
  final double effectiveUnit; // weighted-average effective unit after applying threshold discounts across all purchases
  final double? threshold; // subtotal threshold to apply discount; null if not configured
  final double thresholdDiscountPercent; // e.g., 30

  // NEW semantics (preferred):
  // discountPercent = % discount applied to ACCESS FEE at redemption.
  final int discountPercent; // 0..100

  // Legacy/back-compat fields (keep reading/writing so old UI doesn't break)
  final int userPaysPercent; // derived = 100 - discountPercent
  final int organizerPaysPercent; // legacy (unused in new model)

  // Quantities
  final int qtyTotal; // total purchased over time
  final int qtyRemaining; // remaining to be redeemed

  // Metadata
  final int createdAtMs;
  final int updatedAtMs;
  final int version;

  const CouponConfig({
    required this.leagueId,
    required this.organizerUserId,
    required this.currency,
    required this.unitPrice,
    required this.effectiveUnit,
    required this.threshold,
    required this.thresholdDiscountPercent,
    required this.discountPercent,
    required this.userPaysPercent,
    required this.organizerPaysPercent,
    required this.qtyTotal,
    required this.qtyRemaining,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.version,
  });

  int get qtyRedeemed => qtyTotal - qtyRemaining;

  Map<String, dynamic> toMap() {
    final int disc = discountPercent.clamp(0, 100);
    final int usersPay = (100 - disc).clamp(0, 100);

    final String c = currency.trim().toUpperCase();

    return <String, dynamic>{
      'leagueId': leagueId,
      'organizerUserId': organizerUserId, // display only (rules should not depend on it)
      'currency': c,
      'unitPrice': unitPrice,
      'effectiveUnit': effectiveUnit,
      'threshold': threshold,
      'thresholdDiscountPercent': thresholdDiscountPercent,

      // preferred
      'discountPercent': disc,

      // legacy/back-compat (keep)
      'userPaysPercent': usersPay,
      'organizerPaysPercent': 100,

      'qtyTotal': qtyTotal,
      'qtyRemaining': qtyRemaining,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'version': version,
    };
  }

  factory CouponConfig.fromMap(Map<String, dynamic> map, String leagueId) {
    double _toDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    int _toInt(dynamic v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    String _toStr(dynamic v) => (v is String) ? v : '';

    final hasThresholdKey = map.containsKey('threshold');
    final rawThreshold = hasThresholdKey ? map['threshold'] : null;
    final threshold = rawThreshold == null ? null : _toDouble(rawThreshold);

    // Prefer discountPercent, else derive from legacy userPaysPercent.
    final bool hasDisc = map.containsKey('discountPercent') && map['discountPercent'] is num;
    final int disc = hasDisc
        ? _toInt(map['discountPercent'], fallback: 0).clamp(0, 100)
        : (100 - _toInt(map['userPaysPercent'], fallback: 0)).clamp(0, 100);

    final int usersPayDerived = (100 - disc).clamp(0, 100);

    final currency = _toStr(map['currency']).trim().toUpperCase();

    return CouponConfig(
      leagueId: leagueId,
      organizerUserId: _toStr(map['organizerUserId']),
      currency: currency,
      unitPrice: _toDouble(map['unitPrice']),
      effectiveUnit: _toDouble(map['effectiveUnit'], fallback: _toDouble(map['unitPrice'])),
      threshold: threshold,
      thresholdDiscountPercent: _toDouble(map['thresholdDiscountPercent'], fallback: 30.0),
      discountPercent: disc,
      userPaysPercent: _toInt(map['userPaysPercent'], fallback: usersPayDerived).clamp(0, 100),
      organizerPaysPercent: _toInt(map['organizerPaysPercent'], fallback: 100).clamp(0, 100),
      qtyTotal: _toInt(map['qtyTotal'], fallback: 0),
      qtyRemaining: _toInt(map['qtyRemaining'], fallback: 0),
      createdAtMs: _toInt(map['createdAtMs'], fallback: 0),
      updatedAtMs: _toInt(map['updatedAtMs'], fallback: 0),
      version: _toInt(map['version'], fallback: 1),
    );
  }
}

class CouponConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _configRef(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('couponConfig').doc('config');
  }

  DocumentReference<Map<String, dynamic>> _leagueRef(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId);
  }

  // Read helpers --------------------------------------------------------------

  Future<CouponConfig?> getConfig(String leagueId) async {
    final snap = await _configRef(leagueId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return CouponConfig.fromMap(data, leagueId);
  }

  Stream<CouponConfig?> watchConfig(String leagueId) {
    return _configRef(leagueId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return CouponConfig.fromMap(data, leagueId);
    });
  }

  // Internal helpers ----------------------------------------------------------

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) {
      throw StateError('Not signed in (no Firebase UID).');
    }
    return uid.trim();
  }

  String _normalizeCurrency(String raw) {
    final c = raw.trim().toUpperCase();
    if (c != 'NGN' && c != 'USD') {
      throw StateError('Invalid currency "$raw" (must be NGN or USD).');
    }
    return c;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  bool _boolAny(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return false;
  }

  int _intAny(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _strAny(dynamic v, {String fallback = ''}) => (v is String) ? v : fallback;

  Map<String, dynamic>? _mapAny(dynamic v) => (v is Map) ? v.cast<String, dynamic>() : null;

  /// Auto-initialize (or repair) `leagues/{leagueId}/couponConfig/config`.
  ///
  /// IMPORTANT:
  /// Firestore rules require unitPrice/effectiveUnit > 0 on create.
  /// So we initialize them with a safe >0 placeholder (1.0).
  /// Purchase flow will overwrite with real values from RemotePricingPlan.
  Future<void> ensureConfigInitializedFromLeague(String leagueId) async {
    final authUid = _requireAuthUid();
    final ref = _configRef(leagueId);

    await _firestore.runTransaction((tx) async {
      final nowWallMs = DateTime.now().millisecondsSinceEpoch;

      final cfgSnap = await tx.get(ref);
      if (cfgSnap.exists) {
        final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

        // Repair missing qtyRemaining using ONLY allowed update keys.
        final hasQtyRemaining = cfg.containsKey('qtyRemaining') && (cfg['qtyRemaining'] is num);
        if (!hasQtyRemaining) {
          final int prevUpdatedAtMs = (cfg['updatedAtMs'] as num?)?.toInt() ?? 0;
          final int writeNowMs = (nowWallMs > prevUpdatedAtMs) ? nowWallMs : (prevUpdatedAtMs + 1);

          tx.update(ref, <String, dynamic>{
            'qtyRemaining': 0,
            'updatedAtMs': writeNowMs,
          });
        }
        return;
      }

      // Config is missing → verify league ownership before creating anything.
      final leagueSnap = await tx.get(_leagueRef(leagueId));
      if (!leagueSnap.exists) throw StateError('leagueMissing');

      final ld = (leagueSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

      bool isLeagueOwner = false;
      final orgUid = _strAny(ld['organizerUid']);
      final ownerUid = _strAny(ld['ownerUid']);
      final orgUserId = _strAny(ld['organizerUserId']);
      final ownerId = _strAny(ld['ownerId']);

      if (orgUid == authUid) isLeagueOwner = true;
      if (ownerUid == authUid) isLeagueOwner = true;

      // Backward compat (ONLY if those happen to be Firebase UIDs in older deployments)
      if (orgUserId == authUid) isLeagueOwner = true;
      if (ownerId == authUid) isLeagueOwner = true;

      if (!isLeagueOwner) throw StateError('notOrganizer');

      // Support multiple possible locations for league settings (top-level or nested).
      final settings = _mapAny(ld['settings']) ?? <String, dynamic>{};

      final bool couponsEnabled = _boolAny(ld['couponsEnabled']) || _boolAny(settings['couponsEnabled']);
      final int couponCount = _intAny(ld['couponCount'], fallback: _intAny(settings['couponCount'], fallback: 0));

      // Try to seed discountPercent from league (legacy compatibility).
      final int seededDiscount = (() {
        final int d1 = _intAny(ld['couponDiscountPercent'], fallback: -1);
        final int d2 = _intAny(settings['couponDiscountPercent'], fallback: -1);
        if (d1 >= 0) return d1.clamp(0, 100);
        if (d2 >= 0) return d2.clamp(0, 100);

        // Legacy: userPaysPercent -> discount = 100 - userPaysPercent
        final int up1 = _intAny(ld['userPaysPercent'], fallback: -1);
        final int up2 = _intAny(settings['userPaysPercent'], fallback: -1);
        if (up1 >= 0) return (100 - up1).clamp(0, 100);
        if (up2 >= 0) return (100 - up2).clamp(0, 100);

        return 0;
      })();

      // Currency hint (best-effort): keep valid values only.
      String currency = _strAny(ld['currency'], fallback: _strAny(settings['currency'], fallback: 'USD'));
      currency = currency.trim().toUpperCase();
      if (currency != 'NGN' && currency != 'USD') currency = 'USD';

      final int seedQty = (couponsEnabled && couponCount > 0) ? couponCount : 0;
      final int createdAtMs = nowWallMs > 0 ? nowWallMs : 1;

      // Must be >0 to satisfy rules on create.
      final double initUnitPrice = _round2(1.0);
      final double initEffectiveUnit = _round2(1.0);

      tx.set(ref, <String, dynamic>{
        'leagueId': leagueId,
        'organizerUserId': authUid, // informational; rules rely on league.organizerUid
        'currency': currency,

        'unitPrice': initUnitPrice,
        'effectiveUnit': initEffectiveUnit,
        'threshold': null,
        'thresholdDiscountPercent': 30.0,

        'discountPercent': seededDiscount,
        'userPaysPercent': (100 - seededDiscount).clamp(0, 100),
        'organizerPaysPercent': 100,

        'qtyTotal': seedQty,
        'qtyRemaining': seedQty,
        'createdAtMs': createdAtMs,
        'updatedAtMs': createdAtMs,
        'version': 1,
      });
    });
  }

  // Create or increment configuration atomically after payment ---------------

  Future<void> createOrIncrementOnPurchase({
    required String leagueId,
    required String organizerUserId,
    required int qtyPurchased,
    int? discountPercent,
    int? userPaysPercent,
    required RemotePricingPlan plan,
  }) async {
    final authUid = _requireAuthUid();

    // Canonical: write auth UID (never short id) to be consistent with UID-authoritative model.
    final String organizerUidForWrite = authUid;

    final int qty = qtyPurchased < 0 ? 0 : qtyPurchased;

    final int disc = (discountPercent != null)
        ? discountPercent.clamp(0, 100)
        : (100 - (userPaysPercent ?? 0)).clamp(0, 100);

    final int usersPay = (100 - disc).clamp(0, 100);

    final ref = _configRef(leagueId);

    final currency = _normalizeCurrency(plan.currency);
    final couponUnit = plan.couponUnit;

    if (couponUnit <= 0) {
      throw StateError('Pricing misconfigured: couponUnit must be > 0.');
    }

    // Compute discounted subtotal for this batch and effective unit for the batch
    double batchSubtotal = couponUnit * qty;
    if (qty > 0 &&
        plan.couponThreshold != null &&
        plan.couponThreshold! > 0 &&
        batchSubtotal >= plan.couponThreshold!) {
      final pct = (plan.couponDiscountPercent <= 0) ? 0 : plan.couponDiscountPercent;
      batchSubtotal = batchSubtotal * ((100.0 - pct) / 100.0);
    }
    final double batchEffectiveUnit = qty > 0 ? _round2(batchSubtotal / qty) : _round2(couponUnit);

    await _firestore.runTransaction((tx) async {
      // READS first
      final snap = await tx.get(ref);
      final nowWallMs = DateTime.now().millisecondsSinceEpoch;

      if (!snap.exists) {
        // Create
        final int createdAtMs = nowWallMs > 0 ? nowWallMs : 1;
        final data = <String, dynamic>{
          'leagueId': leagueId,
          'organizerUserId': organizerUidForWrite, // display only; auth is via league.organizerUid in rules
          'currency': currency,
          'unitPrice': _round2(couponUnit),
          'effectiveUnit': _round2(batchEffectiveUnit),
          'threshold': plan.couponThreshold,
          'thresholdDiscountPercent': plan.couponDiscountPercent,

          'discountPercent': disc,

          // legacy/back-compat
          'userPaysPercent': usersPay,
          'organizerPaysPercent': 100,

          'qtyTotal': qty,
          'qtyRemaining': qty,
          'createdAtMs': createdAtMs,
          'updatedAtMs': createdAtMs,
          'version': 1,
        };
        tx.set(ref, data);
        return;
      }

      // Update/increment
      final existing = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final existingOrganizer = (existing['organizerUserId'] as String?) ?? '';

      // If config "belongs" to a legacy id (short/shareId), don't block here.
      // Instead verify league ownership by Firebase UID.
      if (existingOrganizer.isNotEmpty && existingOrganizer != organizerUidForWrite) {
        final leagueSnap = await tx.get(_leagueRef(leagueId));
        if (!leagueSnap.exists) {
          throw StateError('leagueMissing');
        }
        final ld = (leagueSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

        bool isLeagueOwner = false;
        final orgUid = (ld['organizerUid'] as String?) ?? '';
        final ownerUid = (ld['ownerUid'] as String?) ?? '';
        final orgUserId = (ld['organizerUserId'] as String?) ?? '';
        final ownerId = (ld['ownerId'] as String?) ?? '';

        if (orgUid == organizerUidForWrite) isLeagueOwner = true;
        if (ownerUid == organizerUidForWrite) isLeagueOwner = true;

        // Backward compat (ONLY if those happen to be Firebase UIDs in older deployments)
        if (orgUserId == organizerUidForWrite) isLeagueOwner = true;
        if (ownerId == organizerUidForWrite) isLeagueOwner = true;

        if (!isLeagueOwner) {
          throw StateError('notOrganizer');
        }
      }

      final int prevTotal = (existing['qtyTotal'] as num?)?.toInt() ?? 0;
      final int prevRemaining = (existing['qtyRemaining'] as num?)?.toInt() ?? 0;

      final double prevEffectiveUnit = (existing['effectiveUnit'] is num)
          ? (existing['effectiveUnit'] as num).toDouble()
          : (existing['unitPrice'] is num)
              ? (existing['unitPrice'] as num).toDouble()
              : couponUnit;

      final int newTotal = prevTotal + qty;
      final int newRemaining = prevRemaining + qty;

      final double newEffectiveUnit = newTotal > 0
          ? _round2(((prevEffectiveUnit * prevTotal) + (batchEffectiveUnit * qty)) / newTotal)
          : _round2(prevEffectiveUnit);

      // Ensure updatedAtMs strictly increases (some rules require >)
      final int prevUpdatedAtMs = (existing['updatedAtMs'] as num?)?.toInt() ?? 0;
      final int writeNowMs = (nowWallMs > prevUpdatedAtMs) ? nowWallMs : (prevUpdatedAtMs + 1);

      final update = <String, dynamic>{
        'currency': currency,
        'unitPrice': _round2(couponUnit),
        'effectiveUnit': newEffectiveUnit,
        'threshold': plan.couponThreshold,
        'thresholdDiscountPercent': plan.couponDiscountPercent,

        'discountPercent': disc,

        // legacy/back-compat
        'userPaysPercent': usersPay,
        'organizerPaysPercent': 100,

        'qtyTotal': newTotal,
        'qtyRemaining': newRemaining,
        'updatedAtMs': writeNowMs,
      };

      tx.set(ref, update, SetOptions(merge: true));
    });
  }
}
