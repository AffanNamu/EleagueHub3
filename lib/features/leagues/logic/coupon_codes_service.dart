import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/remote_pricing_service.dart';
import 'league_charges_payment_service.dart';

class CouponCodeRedeemResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final double amountCharged;
  final String currency;
  final String? errorMessage;

  const CouponCodeRedeemResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.amountCharged,
    required this.currency,
    required this.errorMessage,
  });

  factory CouponCodeRedeemResult.success({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required double amountCharged,
    required String currency,
  }) {
    return CouponCodeRedeemResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      amountCharged: amountCharged,
      currency: currency,
      errorMessage: null,
    );
  }

  factory CouponCodeRedeemResult.free({
    required int paidAtMs,
    required String currency,
  }) {
    return CouponCodeRedeemResult._(
      success: true,
      receiptId: 'CPN-CODE-FREE',
      paidAtMs: paidAtMs,
      provider: 'coupon',
      amountCharged: 0.0,
      currency: currency,
      errorMessage: null,
    );
  }

  factory CouponCodeRedeemResult.failed({
    required String errorMessage,
    String currency = '',
  }) {
    return CouponCodeRedeemResult._(
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

class CouponCodesService {
  CouponCodesService({
    LeagueChargesPaymentService? paymentService,
  }) : _payment = paymentService ?? FlutterwaveLeagueChargesPaymentService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LeagueChargesPaymentService _payment;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random _rnd = Random.secure();

  String _genCode(int len) {
    final b = StringBuffer();
    for (int i = 0; i < len; i++) {
      b.write(_alphabet[_rnd.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));
  String _moneyStr(double v) {
    final r = _round2(v);
    final i = r.toInt();
    if ((r - i).abs() < 0.000001) return '$i';
    return r.toStringAsFixed(2);
  }

  DocumentReference<Map<String, dynamic>> _cfgRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponConfig').doc('config');

  DocumentReference<Map<String, dynamic>> _codeRef(String leagueId, String code) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponCodes').doc(code);

  DocumentReference<Map<String, dynamic>> _redeemRef(String leagueId, String uid) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponRedemptions').doc(uid);

  // Generate 'count' new codes; each code decrements qtyRemaining by 1 atomically with rules.
  // organizerAuthUid must be the Firebase UID of the organizer (rules check).
  Future<List<String>> generateCodes({
    required String leagueId,
    required String organizerAuthUid,
    required int count,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final List<String> out = [];

    for (int i = 0; i < count; i++) {
      String code = '';
      int attempts = 0;

      while (true) {
        if (attempts > 8) {
          throw StateError('Could not allocate a unique code after several attempts.');
        }
        code = 'EH${_genCode(10)}';
        attempts++;

        final docRef = _codeRef(leagueId, code);

        try {
          await _firestore.runTransaction((tx) async {
            final cfgSnap = await tx.get(_cfgRef(leagueId));
            if (!cfgSnap.exists) {
              throw StateError('noConfig');
            }
            final cfg = cfgSnap.data() ?? <String, dynamic>{};
            final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
            final currency = (cfg['currency'] as String?) ?? 'USD';
            final usersPayPercent = (cfg['userPaysPercent'] as num?)?.toInt() ?? 0;
            final effectiveUnit = (cfg['effectiveUnit'] as num?)?.toDouble() ?? 0.0;

            if (remaining <= 0) {
              throw StateError('noRemaining');
            }

            // Check collision
            final codeSnap = await tx.get(docRef);
            if (codeSnap.exists) {
              throw StateError('collision');
            }

            final expectedAmount = _round2(effectiveUnit * (usersPayPercent / 100.0));

            tx.set(docRef, <String, dynamic>{
              'leagueId': leagueId,
              'organizerUserId': organizerAuthUid,
              'currency': currency,
              'expectedAmount': expectedAmount,
              'usedBy': '',
              'usedAtMs': 0,
              'createdAtMs': nowMs,
              'updatedAtMs': nowMs,
              'version': 1,
            });

            tx.update(_cfgRef(leagueId), <String, dynamic>{
              'qtyRemaining': remaining - 1,
              'updatedAtMs': nowMs,
            });
          });

          out.add(code);
          break; // success for this code
        } on StateError catch (e) {
          if (e.message == 'collision') {
            continue; // try a new code
          }
          rethrow;
        }
      }
    }

    return out;
  }

  // Redeem a code: pay expectedAmount if > 0, then atomically mark code used and create 'paid' redemption.
  Future<CouponCodeRedeemResult> redeemWithCode({
    required BuildContext context,
    required String leagueId,
    required String leagueName,
    required String userId,
    required String code,
  }) async {
    final codeId = code.trim().toUpperCase();
    if (codeId.isEmpty) {
      return CouponCodeRedeemResult.failed(errorMessage: 'Empty code');
    }

    try {
      final codeRef = _codeRef(leagueId, codeId);
      final snap = await codeRef.get();
      if (!snap.exists) return CouponCodeRedeemResult.failed(errorMessage: 'Invalid code');

      final data = snap.data() ?? <String, dynamic>{};
      final usedBy = (data['usedBy'] as String?) ?? '';
      if (usedBy.isNotEmpty) {
        return CouponCodeRedeemResult.failed(errorMessage: 'Code already used');
      }

      final codeLeagueId = (data['leagueId'] as String?) ?? '';
      if (codeLeagueId != leagueId) {
        return CouponCodeRedeemResult.failed(errorMessage: 'Code does not belong to this league');
      }

      final currency = (data['currency'] as String?) ?? 'USD';
      final expectedAmount = (data['expectedAmount'] as num?)?.toDouble() ?? 0.0;

      int paidAtMs = 0;
      String provider = 'coupon';
      String? receiptId;

      // If user share > 0, collect payment
      if (expectedAmount > 0) {
        final pay = await _payment.payLeagueCharges(
          context: context,
          userId: userId,
          leagueId: leagueId,
          leagueName: leagueName,
          amountOverride: _moneyStr(expectedAmount),
          couponCode: codeId,
          couponDiscountPercent: null,
          currencyOverride: currency,
        );

        if (!pay.success) {
          return CouponCodeRedeemResult.failed(errorMessage: pay.errorMessage ?? 'Payment failed', currency: currency);
        }
        paidAtMs = pay.paidAtMs;
        provider = pay.provider;
        receiptId = pay.receiptId ?? 'FLW-UNKNOWN';
      } else {
        paidAtMs = DateTime.now().millisecondsSinceEpoch;
        provider = 'coupon';
        receiptId = 'CPN-CODE-FREE';
      }

      // Atomically: mark code used and create redemption document (status 'paid')
      await _firestore.runTransaction((tx) async {
        final codeSnap = await tx.get(codeRef);
        if (!codeSnap.exists) throw StateError('invalid');
        final d = codeSnap.data() ?? <String, dynamic>{};
        final wasUsed = (d['usedBy'] as String?) ?? '';
        if (wasUsed.isNotEmpty) throw StateError('used');

        tx.update(codeRef, <String, dynamic>{
          'usedBy': userId,
          'usedAtMs': paidAtMs,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        });

        final rRef = _redeemRef(leagueId, userId);
        tx.set(rRef, <String, dynamic>{
          'leagueId': leagueId,
          'userId': userId,
          'status': 'paid',
          'provider': provider,
          'receiptId': receiptId ?? '',
          'paidAtMs': paidAtMs,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
          'currency': currency,
          'expectedAmount': expectedAmount,
          'code': codeId,
          'version': 1,
        });
      });

      return CouponCodeRedeemResult.success(
        receiptId: receiptId ?? 'CPN',
        paidAtMs: paidAtMs,
        provider: provider,
        amountCharged: expectedAmount,
        currency: currency,
      );
    } on StateError catch (e) {
      final msg = e.message ?? 'Redemption failed';
      return CouponCodeRedeemResult.failed(errorMessage: msg);
    } catch (e) {
      return CouponCodeRedeemResult.failed(errorMessage: e.toString());
    }
  }
}
