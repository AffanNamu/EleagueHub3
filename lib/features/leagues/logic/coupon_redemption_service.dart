import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/remote_pricing_service.dart';
import '../models/league.dart';
import 'league_charges_payment_service.dart';
import 'coupon_config_service.dart';

class CouponRedemptionIntent {
  final String leagueId;
  final String userId;
  final String currency;
  final double expectedAmount; // user pays this amount (effectiveUnit * userPaysPercent)
  final int createdAtMs;
  final int expiresAtMs;

  const CouponRedemptionIntent({
    required this.leagueId,
    required this.userId,
    required this.currency,
    required this.expectedAmount,
    required this.createdAtMs,
    required this.expiresAtMs,
  });
}

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
      receiptId: 'CPN-FREE',
      paidAtMs: paidAtMs,
      provider: 'coupon',
      amountCharged: 0.0,
      currency: currency,
      errorMessage: null,
    );
  }

  factory CouponRedemptionResult.failed({
    required String errorMessage,
    required String currency,
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
  }) : _payment = paymentService ?? FlutterwaveLeagueChargesPaymentService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LeagueChargesPaymentService _payment;

  static const Duration _intentTtl = Duration(minutes: 15);

  DocumentReference<Map<String, dynamic>> _cfgRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponConfig').doc('config');

  DocumentReference<Map<String, dynamic>> _intentRef(String leagueId, String userId) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponRedemptions').doc(userId);

  // Round helpers
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _moneyStr(double v) {
    final r = _round2(v);
    final i = r.toInt();
    if ((r - i).abs() < 0.000001) return '$i';
    return r.toStringAsFixed(2);
  }

  // Prepare an intent (idempotent for a user/league).
  // - Ensures at most one redemption per user
  // - Computes expectedAmount using effectiveUnit * (userPaysPercent/100)
  // - Creates a pending intent with TTL
  Future<CouponRedemptionIntent> prepareIntent({
    required String leagueId,
    required String userId,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(_intentTtl);

    final refCfg = _cfgRef(leagueId);
    final refIntent = _intentRef(leagueId, userId);

    final data = await _firestore.runTransaction((tx) async {
      final cfgSnap = await tx.get(refCfg);
      if (!cfgSnap.exists) {
        throw StateError('noConfig');
      }
      final cfg = CouponConfig.fromMap((cfgSnap.data() ?? <String, dynamic>{}), leagueId);

      if (cfg.qtyRemaining <= 0) {
        throw StateError('noRemaining');
      }

      final intentSnap = await tx.get(refIntent);
      if (intentSnap.exists) {
        final d = (intentSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final status = (d['status'] as String?) ?? 'pending';
        final exp = d['expiresAt'];
        if (status == 'paid') {
          // Already redeemed.
          return d;
        }
        if (exp is Timestamp && exp.toDate().isAfter(now)) {
          // Reuse existing pending.
          return d;
        }
        // Expired pending — fallthrough to overwrite.
      }

      final expected = _round2(cfg.effectiveUnit * (cfg.userPaysPercent / 100.0));

      final payload = <String, dynamic>{
        'leagueId': leagueId,
        'userId': userId,
        'status': 'pending',
        'currency': cfg.currency,
        'expectedAmount': expected,
        'createdAtMs': now.millisecondsSinceEpoch,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAtMs': now.millisecondsSinceEpoch,
        'version': 1,
      };
      tx.set(refIntent, payload);
      return payload;
    });

    final currency = (data['currency'] as String?) ?? 'USD';
    final expectedAmount = (data['expectedAmount'] as num?)?.toDouble() ?? 0.0;
    final createdAtMs = (data['createdAtMs'] as num?)?.toInt() ?? 0;
    final expiresAtTs = data['expiresAt'];
    final expiresAtMs = (expiresAtTs is Timestamp) ? expiresAtTs.toDate().millisecondsSinceEpoch : (createdAtMs + _intentTtl.inMilliseconds);

    return CouponRedemptionIntent(
      leagueId: leagueId,
      userId: userId,
      currency: currency,
      expectedAmount: expectedAmount,
      createdAtMs: createdAtMs,
      expiresAtMs: expiresAtMs,
    );
  }

  // Commit the redemption:
  // - If expectedAmount > 0: collect payment via LeagueChargesPaymentService (same provider, currency forced to config currency)
  // - In a Firestore transaction: verify pending+not expired, qtyRemaining>0, decrement remaining, mark intent as paid with receipt.
  Future<CouponRedemptionResult> redeemNow({
    required BuildContext context,
    required League league,
    required String userId,
  }) async {
    final leagueId = league.id;
    final refCfg = _cfgRef(leagueId);
    final refIntent = _intentRef(leagueId, userId);

    try {
      // 1) Make sure we have a fresh/pending intent (or existing paid)
      final intent = await prepareIntent(leagueId: leagueId, userId: userId);
      final expected = _round2(intent.expectedAmount);
      final currency = intent.currency;

      // 2) If free (admin pays 100%), finalize directly
      if (expected <= 0.0) {
        final now = DateTime.now();
        await _firestore.runTransaction((tx) async {
          final cfgSnap = await tx.get(refCfg);
          if (!cfgSnap.exists) throw StateError('noConfig');

          final cfg = CouponConfig.fromMap((cfgSnap.data() ?? <String, dynamic>{}), leagueId);
          if (cfg.qtyRemaining <= 0) throw StateError('noRemaining');

          final intentSnap = await tx.get(refIntent);
          if (!intentSnap.exists) throw StateError('noIntent');
          final d = (intentSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
          final status = (d['status'] as String?) ?? 'pending';
          if (status == 'paid') {
            // Idempotent success
            return;
          }
          final exp = d['expiresAt'];
          if (exp is Timestamp && exp.toDate().isBefore(now)) {
            throw StateError('expired');
          }

          tx.update(refCfg, <String, dynamic>{
            'qtyRemaining': cfg.qtyRemaining - 1,
            'updatedAtMs': now.millisecondsSinceEpoch,
          });

          tx.update(refIntent, <String, dynamic>{
            'status': 'paid',
            'provider': 'coupon',
            'receiptId': 'CPN-FREE',
            'paidAtMs': now.millisecondsSinceEpoch,
            'updatedAtMs': now.millisecondsSinceEpoch,
          });
        });

        return CouponRedemptionResult.free(
          paidAtMs: DateTime.now().millisecondsSinceEpoch,
          currency: currency,
        );
      }

      // 3) Collect payment (amount in config currency). We pass amountOverride and currencyOverride.
      final pay = await _payment.payLeagueCharges(
        context: context,
        userId: userId,
        leagueId: leagueId,
        leagueName: league.name,
        amountOverride: _moneyStr(expected),
        // No per-code coupon; mark as POOL in description to trace this was a pool redemption.
        couponCode: 'POOL',
        couponDiscountPercent: null,
        currencyOverride: currency, // CRITICAL: force currency to match coupon config currency
      );

      if (!pay.success) {
        return CouponRedemptionResult.failed(
          errorMessage: pay.errorMessage ?? 'Payment failed',
          currency: currency,
        );
      }

      final receipt = pay.receiptId ?? 'FLW-UNKNOWN';
      final paidAtMs = pay.paidAtMs;

      // 4) Finalize usage atomically (decrement remaining + mark intent paid)
      await _firestore.runTransaction((tx) async {
        final cfgSnap = await tx.get(refCfg);
        if (!cfgSnap.exists) throw StateError('noConfig');

        final cfg = CouponConfig.fromMap((cfgSnap.data() ?? <String, dynamic>{}), leagueId);
        if (cfg.qtyRemaining <= 0) throw StateError('noRemaining');

        final intentSnap = await tx.get(refIntent);
        if (!intentSnap.exists) throw StateError('noIntent');
        final d = (intentSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final status = (d['status'] as String?) ?? 'pending';
        if (status == 'paid') {
          // Idempotent success
          return;
        }
        final exp = d['expiresAt'];
        if (exp is Timestamp && exp.toDate().isBefore(DateTime.now())) {
          throw StateError('expired');
        }

        tx.update(refCfg, <String, dynamic>{
          'qtyRemaining': cfg.qtyRemaining - 1,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        });

        tx.update(refIntent, <String, dynamic>{
          'status': 'paid',
          'provider': pay.provider,
          'receiptId': receipt,
          'paidAtMs': paidAtMs,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        });
      });

      return CouponRedemptionResult.success(
        receiptId: receipt,
        paidAtMs: paidAtMs,
        provider: pay.provider,
        amountCharged: expected,
        currency: currency,
      );
    } on StateError catch (e) {
      final code = e.message ?? 'error';
      String msg = 'Redemption failed';
      if (code == 'noConfig') msg = 'Coupons are not configured for this league.';
      if (code == 'noRemaining') msg = 'No coupons remaining. Please contact the organizer.';
      if (code == 'noIntent') msg = 'Redemption intent missing. Try again.';
      if (code == 'expired') msg = 'Your redemption session expired. Please try again.';
      return CouponRedemptionResult.failed(errorMessage: msg, currency: 'USD');
    } catch (e) {
      return CouponRedemptionResult.failed(errorMessage: e.toString(), currency: 'USD');
    }
  }
}
