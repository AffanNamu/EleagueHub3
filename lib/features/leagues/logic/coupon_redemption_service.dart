import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/league.dart';
import 'league_charges_payment_service.dart';

class CouponRedemptionResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final double amountCharged;
  final String currency;
  final String? errorMessage;

  const CouponRedemptionResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.amountCharged,
    required this.currency,
    required this.errorMessage,
  });

  factory CouponRedemptionResult.success({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required double amountCharged,
    required String currency,
  }) {
    return CouponRedemptionResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      amountCharged: amountCharged,
      currency: currency,
      errorMessage: null,
    );
  }

  factory CouponRedemptionResult.free({
    required int paidAtMs,
    required String currency,
  }) {
    return CouponRedemptionResult._(
      success: true,
      receiptId: 'CPN-POOL-FREE',
      paidAtMs: paidAtMs,
      provider: 'coupon',
      amountCharged: 0.0,
      currency: currency,
      errorMessage: null,
    );
  }

  factory CouponRedemptionResult.failed({
    required String errorMessage,
    String currency = '',
  }) {
    return CouponRedemptionResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: 'coupon',
      amountCharged: 0.0,
      currency: currency,
      errorMessage: errorMessage,
    );
  }
}

class CouponRedemptionService {
  CouponRedemptionService({
    LeagueChargesPaymentService? paymentService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _payment = paymentService ?? FlutterwaveLeagueChargesPaymentService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LeagueChargesPaymentService _payment;

  DocumentReference<Map<String, dynamic>> _cfgRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponConfig').doc('config');

  DocumentReference<Map<String, dynamic>> _redeemRef(String leagueId, String uid) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponRedemptions').doc(uid);

  DocumentReference<Map<String, dynamic>> _pricingRef() => _firestore.collection('app').doc('pricing');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) {
      throw StateError('Not signed in (no Firebase UID).');
    }
    return uid.trim();
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _moneyStr(String currency, double v) {
    final c = currency.toUpperCase();
    if (c == 'NGN') return '${v.round()}';
    final r = _round2(v);
    final i = r.toInt();
    if ((r - i).abs() < 0.000001) return '$i';
    return r.toStringAsFixed(2);
  }

  int _discountPercentFromConfig(Map<String, dynamic> cfg) {
    // preferred: discountPercent
    if (cfg.containsKey('discountPercent') && cfg['discountPercent'] is num) {
      return (cfg['discountPercent'] as num).toInt().clamp(0, 100);
    }
    // legacy: userPaysPercent -> discount = 100 - userPaysPercent
    final up = (cfg['userPaysPercent'] as num?)?.toInt() ?? 0;
    return (100 - up).clamp(0, 100);
  }

  double _accessFeeForCurrency(Map<String, dynamic> pricing, String currency) {
    try {
      final c = currency.toUpperCase();
      final plan = (c == 'NGN')
          ? (pricing['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{}
          : (pricing['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final v = plan['accessFee'];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0.0;
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  _ResolvedAccessFee _resolveAccessFeeWithFallback(Map<String, dynamic> pricing, String preferredCurrency) {
    final pref = preferredCurrency.toUpperCase();
    double fee = _accessFeeForCurrency(pricing, pref);
    if (fee > 0) return _ResolvedAccessFee(currency: pref, accessFee: fee);

    // Fallback to the other currency if misconfigured (resilience)
    final other = (pref == 'NGN') ? 'USD' : 'NGN';
    fee = _accessFeeForCurrency(pricing, other);
    return _ResolvedAccessFee(currency: other, accessFee: fee);
  }

  Future<_ExpectedPoolCharge> _computeExpectedFromConfigTx(Transaction tx, String leagueId) async {
    final cfgSnap = await tx.get(_cfgRef(leagueId));
    if (!cfgSnap.exists) throw StateError('noConfig');
    final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
    if (remaining <= 0) throw StateError('noRemaining');

    final cfgCurrency = ((cfg['currency'] as String?) ?? 'USD').toUpperCase();
    final discountPercent = _discountPercentFromConfig(cfg);

    final pricingSnap = await tx.get(_pricingRef());
    final pricingMap = (pricingSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final resolved = _resolveAccessFeeWithFallback(pricingMap, cfgCurrency);
    if (resolved.accessFee <= 0) throw StateError('pricingMissing');

    final raw = resolved.accessFee * ((100 - discountPercent) / 100.0);
    final expected = (resolved.currency == 'NGN') ? raw.roundToDouble() : _round2(raw);

    return _ExpectedPoolCharge(
      currency: resolved.currency, // may differ from cfg currency if pricing is misconfigured
      expectedAmount: expected,
      discountPercent: discountPercent,
      remaining: remaining,
    );
  }

  Future<_ExpectedPoolCharge> _computeExpectedFromConfig(String leagueId) async {
    final cfgSnap = await _cfgRef(leagueId).get();
    if (!cfgSnap.exists) throw StateError('noConfig');
    final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
    if (remaining <= 0) throw StateError('noRemaining');

    final cfgCurrency = ((cfg['currency'] as String?) ?? 'USD').toUpperCase();
    final discountPercent = _discountPercentFromConfig(cfg);

    final pricingSnap = await _pricingRef().get();
    final pricingMap = (pricingSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final resolved = _resolveAccessFeeWithFallback(pricingMap, cfgCurrency);
    if (resolved.accessFee <= 0) throw StateError('pricingMissing');

    final raw = resolved.accessFee * ((100 - discountPercent) / 100.0);
    final expected = (resolved.currency == 'NGN') ? raw.roundToDouble() : _round2(raw);

    return _ExpectedPoolCharge(
      currency: resolved.currency,
      expectedAmount: expected,
      discountPercent: discountPercent,
      remaining: remaining,
    );
  }

  /// Create a pending redemption intent IF MISSING.
  ///
  /// IMPORTANT (rules):
  /// - couponRedemptions/{uid} doc id must equal request.auth.uid
  /// - request.resource.data.userId must equal request.auth.uid
  /// - Rules typically do NOT allow updating an existing pending intent (only pending->paid),
  ///   so this method must NOT write if the doc already exists.
  Future<void> preparePoolRedemption({
    required String leagueId,
    required String userId,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final authUid = _requireAuthUid();

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    await _firestore.runTransaction((tx) async {
      final rRef = _redeemRef(leagueId, authUid);
      final rSnap = await tx.get(rRef);

      if (rSnap.exists) {
        final rd = (rSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final status = (rd['status'] as String?) ?? '';
        if (status == 'paid') throw StateError('alreadyPaid');
        // Leave pending as-is to avoid permission denied.
        return;
      }

      // Compute expected inside tx so it matches config+pricing at that moment.
      final exp = await _computeExpectedFromConfigTx(tx, leagueId);

      tx.set(rRef, <String, dynamic>{
        'leagueId': leagueId,
        'userId': authUid,
        'status': 'pending',
        'currency': exp.currency,
        'expectedAmount': exp.expectedAmount,
        'expiresAt': Timestamp.fromDate(now.add(ttl)),
        'provider': '',
        'receiptId': '',
        'paidAtMs': 0,
        'createdAtMs': nowMs,
        'updatedAtMs': nowMs,
        'version': 1,
      });
    });
  }

  /// Backward-compatible entry used by your current UI.
  /// `userId` is kept for payment metadata, but Firestore writes use Firebase UID.
  Future<CouponRedemptionResult> redeemNow({
    required BuildContext context,
    required League league,
    required String userId,
  }) {
    return redeemFromPool(
      context: context,
      leagueId: league.id,
      leagueName: league.name,
      userId: userId,
    );
  }

  /// Pool redemption:
  /// expectedAmount = accessFee × (1 - discountPercent/100)
  Future<CouponRedemptionResult> redeemFromPool({
    required BuildContext context,
    required String leagueId,
    required String leagueName,
    required String userId,
  }) async {
    String authUid;
    try {
      authUid = _requireAuthUid();
    } on StateError catch (e) {
      return CouponRedemptionResult.failed(errorMessage: e.message ?? 'Not signed in');
    }

    try {
      // 1) Create pending intent if missing (rules-friendly)
      await preparePoolRedemption(leagueId: leagueId, userId: userId);

      // 2) Read pending (doc id == auth uid)
      final rSnap = await _redeemRef(leagueId, authUid).get();

      String currency = 'USD';
      double expectedAmount = 0.0;

      if (rSnap.exists) {
        final r = (rSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        currency = ((r['currency'] as String?) ?? 'USD').toUpperCase();
        expectedAmount = (r['expectedAmount'] as num?)?.toDouble() ?? 0.0;
      } else {
        // If doc couldn't be created (transient), compute directly.
        final exp = await _computeExpectedFromConfig(leagueId);
        currency = exp.currency;
        expectedAmount = exp.expectedAmount;
      }

      int paidAtMs;
      String provider;
      String receiptId;

      // 3) Pay (if needed)
      if (expectedAmount > 0) {
        final pay = await _payment.payLeagueCharges(
          context: context,
          userId: userId, // legacy/local id may be used by the payment provider
          leagueId: leagueId,
          leagueName: leagueName,
          amountOverride: _moneyStr(currency, expectedAmount),
          couponCode: 'POOL',
          couponDiscountPercent: null,
          currencyOverride: currency,
        );

        if (!pay.success) {
          return CouponRedemptionResult.failed(
            errorMessage: pay.errorMessage ?? 'Payment failed',
            currency: currency,
          );
        }

        paidAtMs = pay.paidAtMs;
        provider = pay.provider;
        receiptId = pay.receiptId ?? 'PAY-UNKNOWN';
      } else {
        paidAtMs = DateTime.now().millisecondsSinceEpoch;
        provider = 'coupon';
        receiptId = 'CPN-POOL-FREE';
      }

      // 4) Atomic write: mark redemption paid + decrement qtyRemaining
      await _firestore.runTransaction((tx) async {
        final cfgSnap = await tx.get(_cfgRef(leagueId));
        if (!cfgSnap.exists) throw StateError('noConfig');
        final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
        if (remaining <= 0) throw StateError('noRemaining');

        final rRef = _redeemRef(leagueId, authUid);
        final r2 = await tx.get(rRef);
        if (!r2.exists) throw StateError('noPending');
        final rd = (r2.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        if ((rd['status'] as String?) != 'pending') throw StateError('notPending');

        // Keep updatedAtMs monotonic (nice-to-have; rules already allow this path).
        final prevCfgUpdated = (cfg['updatedAtMs'] as num?)?.toInt() ?? 0;
        final wallNowMs = DateTime.now().millisecondsSinceEpoch;
        final baseNow = wallNowMs > paidAtMs ? wallNowMs : paidAtMs;
        final writeNowMs = baseNow > prevCfgUpdated ? baseNow : (prevCfgUpdated + 1);

        // Rules: changed keys only status/provider/receiptId/paidAtMs/updatedAtMs
        tx.update(rRef, <String, dynamic>{
          'status': 'paid',
          'provider': provider,
          'receiptId': receiptId,
          'paidAtMs': paidAtMs,
          'updatedAtMs': writeNowMs,
        });

        // Rules: config decrement must happen in same request
        tx.update(_cfgRef(leagueId), <String, dynamic>{
          'qtyRemaining': remaining - 1,
          'updatedAtMs': writeNowMs,
        });
      });

      return CouponRedemptionResult.success(
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        provider: provider,
        amountCharged: expectedAmount,
        currency: currency,
      );
    } on StateError catch (e) {
      return CouponRedemptionResult.failed(errorMessage: e.message ?? 'Redemption failed');
    } catch (e) {
      return CouponRedemptionResult.failed(errorMessage: e.toString());
    }
  }
}

class _ExpectedPoolCharge {
  final String currency;
  final double expectedAmount;
  final int discountPercent;
  final int remaining;

  _ExpectedPoolCharge({
    required this.currency,
    required this.expectedAmount,
    required this.discountPercent,
    required this.remaining,
  });
}

class _ResolvedAccessFee {
  final String currency;
  final double accessFee;

  _ResolvedAccessFee({
    required this.currency,
    required this.accessFee,
  });
}
