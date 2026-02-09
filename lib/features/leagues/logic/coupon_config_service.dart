import 'package:cloud_firestore/cloud_firestore.dart';

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

    return <String, dynamic>{
      'leagueId': leagueId,
      'organizerUserId': organizerUserId,
      'currency': currency,
      'unitPrice': unitPrice,
      'effectiveUnit': effectiveUnit,
      'threshold': threshold, // can be null
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

    return CouponConfig(
      leagueId: leagueId,
      organizerUserId: _toStr(map['organizerUserId']),
      currency: _toStr(map['currency']),
      unitPrice: _toDouble(map['unitPrice']),
      effectiveUnit: _toDouble(map['effectiveUnit'], fallback: _toDouble(map['unitPrice'])),
      threshold: threshold,
      thresholdDiscountPercent: _toDouble(map['thresholdDiscountPercent'], fallback: 30.0),

      discountPercent: disc,

      // keep legacy values readable
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

  // Create or increment configuration atomically after payment ---------------

  /// Backward compatible:
  /// - preferred: pass discountPercent
  /// - legacy: pass userPaysPercent (we derive discountPercent = 100 - userPaysPercent)
  Future<void> createOrIncrementOnPurchase({
    required String leagueId,
    required String organizerUserId,
    required int qtyPurchased,
    int? discountPercent,
    int? userPaysPercent,
    required RemotePricingPlan plan,
  }) async {
    final int qty = qtyPurchased < 0 ? 0 : qtyPurchased;

    final int disc = (discountPercent != null)
        ? discountPercent.clamp(0, 100)
        : (100 - (userPaysPercent ?? 0)).clamp(0, 100);

    final int usersPay = (100 - disc).clamp(0, 100);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ref = _configRef(leagueId);

    double _round2(double v) => double.parse(v.toStringAsFixed(2));

    // Compute discounted subtotal for this batch and effective unit for the batch
    double batchSubtotal = plan.couponUnit * qty;
    if (qty > 0 && plan.couponThreshold != null && batchSubtotal >= plan.couponThreshold!) {
      final pct = (plan.couponDiscountPercent <= 0) ? 0 : plan.couponDiscountPercent;
      batchSubtotal = batchSubtotal * ((100.0 - pct) / 100.0);
    }
    final double batchEffectiveUnit = qty > 0 ? _round2(batchSubtotal / qty) : _round2(plan.couponUnit);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);

      if (!snap.exists) {
        final data = <String, dynamic>{
          'leagueId': leagueId,
          'organizerUserId': organizerUserId,
          'currency': plan.currency,
          'unitPrice': _round2(plan.couponUnit),
          'effectiveUnit': _round2(batchEffectiveUnit),
          'threshold': plan.couponThreshold, // can be null
          'thresholdDiscountPercent': plan.couponDiscountPercent,

          // preferred
          'discountPercent': disc,

          // legacy/back-compat (keep)
          'userPaysPercent': usersPay,
          'organizerPaysPercent': 100,

          'qtyTotal': qty,
          'qtyRemaining': qty,
          'createdAtMs': nowMs,
          'updatedAtMs': nowMs,
          'version': 1,
        };
        tx.set(ref, data);
        return;
      }

      final existing = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final existingOrganizer = (existing['organizerUserId'] as String?) ?? '';
      if (existingOrganizer.isNotEmpty && existingOrganizer != organizerUserId) {
        throw StateError('notOrganizer');
      }

      final int prevTotal = (existing['qtyTotal'] as num?)?.toInt() ?? 0;
      final int prevRemaining = (existing['qtyRemaining'] as num?)?.toInt() ?? 0;

      final double prevEffectiveUnit = (existing['effectiveUnit'] is num)
          ? (existing['effectiveUnit'] as num).toDouble()
          : (existing['unitPrice'] is num)
              ? (existing['unitPrice'] as num).toDouble()
              : plan.couponUnit;

      final int newTotal = prevTotal + qty;
      final int newRemaining = prevRemaining + qty;

      // Weighted average across TOTAL purchased (more correct for reporting)
      final double newEffectiveUnit = newTotal > 0
          ? _round2(((prevEffectiveUnit * prevTotal) + (batchEffectiveUnit * qty)) / newTotal)
          : _round2(prevEffectiveUnit);

      final update = <String, dynamic>{
        'currency': plan.currency,
        'unitPrice': _round2(plan.couponUnit),
        'effectiveUnit': newEffectiveUnit,
        'threshold': plan.couponThreshold,
        'thresholdDiscountPercent': plan.couponDiscountPercent,

        // preferred
        'discountPercent': disc,

        // legacy/back-compat (keep)
        'userPaysPercent': usersPay,
        'organizerPaysPercent': 100,

        'qtyTotal': newTotal,
        'qtyRemaining': newRemaining,
        'updatedAtMs': nowMs,
      };

      tx.set(ref, update, SetOptions(merge: true));
    });
  }
}
