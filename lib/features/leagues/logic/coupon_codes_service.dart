import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'coupon_config_service.dart';
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
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    CouponConfigService? configService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _payment = paymentService ?? FlutterwaveLeagueChargesPaymentService(),
        _cfgService = configService ?? CouponConfigService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LeagueChargesPaymentService _payment;
  final CouponConfigService _cfgService;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random _rnd = Random.secure();

  String _genCode(int len) {
    final b = StringBuffer();
    for (int i = 0; i < len; i++) {
      b.write(_alphabet[_rnd.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  String _sanitizeCustomBase(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) throw StateError('Enter a name');
    if (s.contains('/')) throw StateError('Invalid: "/" not allowed');

    s = s.replaceAll(RegExp(r'[\s\-]+'), '_');
    s = s.replaceAll('%', '');
    s = s.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');

    if (s.length < 2) throw StateError('Name too short');
    if (s.length > 40) throw StateError('Name too long');
    return s;
  }

  String _buildCustomCodeId({
    required String base,
    required int discountPercent,
  }) {
    final pct = discountPercent.clamp(0, 100);
    return 'ESL_${base}_$pct%';
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  DocumentReference<Map<String, dynamic>> _cfgRef(String leagueId) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponConfig').doc('config');

  DocumentReference<Map<String, dynamic>> _codeRef(String leagueId, String code) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponCodes').doc(code);

  DocumentReference<Map<String, dynamic>> _redeemRef(String leagueId, String uid) =>
      _firestore.collection('leagues').doc(leagueId).collection('couponRedemptions').doc(uid);

  DocumentReference<Map<String, dynamic>> _pricingRef() => _firestore.collection('app').doc('pricing');

  int _discountPercentFromConfig(Map<String, dynamic> cfg) {
    if (cfg.containsKey('discountPercent') && cfg['discountPercent'] is num) {
      return (cfg['discountPercent'] as num).toInt().clamp(0, 100);
    }
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

  Future<List<String>> generateCodes({
    required String leagueId,
    String? organizerAuthUid,
    required int count,
    String? customCode, // base name: e.g. "BARCA"
  }) async {
    final authUid = _auth.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) throw StateError('Not signed in (no Firebase UID).');

    final customRaw = (customCode ?? '').trim();
    final isCustom = customRaw.isNotEmpty;

    final effectiveCount = isCustom ? 1 : count;
    if (effectiveCount <= 0) return <String>[];

    final organizerUidForWrite =
        (organizerAuthUid != null && organizerAuthUid.trim() == authUid) ? authUid : authUid;

    // Rules require cfgCurrent.exists for couponCodes create => ensure config exists.
    await _cfgService.ensureConfigInitializedFromLeague(leagueId);

    final List<String> out = [];

    if (isCustom) {
      final base = _sanitizeCustomBase(customRaw);

      await _firestore.runTransaction((tx) async {
        final cfgSnap = await tx.get(_cfgRef(leagueId));
        if (!cfgSnap.exists) throw StateError('noConfig');

        final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
        if (remaining <= 0) throw StateError('noRemaining');

        final discountPercent = _discountPercentFromConfig(cfg);
        final codeId = _buildCustomCodeId(base: base, discountPercent: discountPercent);
        final docRef = _codeRef(leagueId, codeId);

        final codeSnap = await tx.get(docRef);
        if (codeSnap.exists) throw StateError('customCollision');

        final pricingSnap = await tx.get(_pricingRef());
        final pricingMap = (pricingSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

        final cfgCurrency = ((cfg['currency'] as String?) ?? 'USD').toUpperCase();
        double accessFee = _accessFeeForCurrency(pricingMap, cfgCurrency);
        String currencyUsed = cfgCurrency;

        if (accessFee <= 0) {
          final other = (cfgCurrency == 'NGN') ? 'USD' : 'NGN';
          final otherFee = _accessFeeForCurrency(pricingMap, other);
          if (otherFee > 0) {
            accessFee = otherFee;
            currencyUsed = other;
          }
        }
        if (accessFee <= 0) throw StateError('pricingMissing');

        final expectedRaw = accessFee * ((100 - discountPercent) / 100.0);
        final expectedAmount = (currencyUsed == 'NGN') ? expectedRaw.roundToDouble() : _round2(expectedRaw);

        final prevUpdatedAtMs = (cfg['updatedAtMs'] as num?)?.toInt() ?? 0;
        final wallNowMs = DateTime.now().millisecondsSinceEpoch;
        final writeNowMs = (wallNowMs > prevUpdatedAtMs) ? wallNowMs : (prevUpdatedAtMs + 1);

        tx.set(docRef, <String, dynamic>{
          'leagueId': leagueId,
          'organizerUserId': organizerUidForWrite, // informational only
          'currency': currencyUsed,
          'discountPercent': discountPercent,
          'expectedAmount': expectedAmount,
          'usedBy': '',
          'usedAtMs': 0,
          'createdAtMs': writeNowMs,
          'updatedAtMs': writeNowMs,
          'version': 1,
        });

        tx.update(_cfgRef(leagueId), <String, dynamic>{
          'qtyRemaining': remaining - 1, // rules require exactly -1
          'updatedAtMs': writeNowMs,
        });

        out.add(codeId);
      });

      return out;
    }

    // Random codes: ESL + 12
    for (int i = 0; i < effectiveCount; i++) {
      int attempts = 0;

      while (true) {
        if (attempts > 10) throw StateError('Could not allocate unique code.');
        attempts++;

        final codeId = 'ESL${_genCode(12)}';
        final docRef = _codeRef(leagueId, codeId);

        try {
          await _firestore.runTransaction((tx) async {
            final cfgSnap = await tx.get(_cfgRef(leagueId));
            if (!cfgSnap.exists) throw StateError('noConfig');

            final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
            final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
            if (remaining <= 0) throw StateError('noRemaining');

            final discountPercent = _discountPercentFromConfig(cfg);

            final pricingSnap = await tx.get(_pricingRef());
            final pricingMap = (pricingSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

            final cfgCurrency = ((cfg['currency'] as String?) ?? 'USD').toUpperCase();
            double accessFee = _accessFeeForCurrency(pricingMap, cfgCurrency);
            String currencyUsed = cfgCurrency;

            if (accessFee <= 0) {
              final other = (cfgCurrency == 'NGN') ? 'USD' : 'NGN';
              final otherFee = _accessFeeForCurrency(pricingMap, other);
              if (otherFee > 0) {
                accessFee = otherFee;
                currencyUsed = other;
              }
            }
            if (accessFee <= 0) throw StateError('pricingMissing');

            final expectedRaw = accessFee * ((100 - discountPercent) / 100.0);
            final expectedAmount = (currencyUsed == 'NGN') ? expectedRaw.roundToDouble() : _round2(expectedRaw);

            final codeSnap = await tx.get(docRef);
            if (codeSnap.exists) throw StateError('collision');

            final prevUpdatedAtMs = (cfg['updatedAtMs'] as num?)?.toInt() ?? 0;
            final wallNowMs = DateTime.now().millisecondsSinceEpoch;
            final writeNowMs = (wallNowMs > prevUpdatedAtMs) ? wallNowMs : (prevUpdatedAtMs + 1);

            tx.set(docRef, <String, dynamic>{
              'leagueId': leagueId,
              'organizerUserId': organizerUidForWrite,
              'currency': currencyUsed,
              'discountPercent': discountPercent,
              'expectedAmount': expectedAmount,
              'usedBy': '',
              'usedAtMs': 0,
              'createdAtMs': writeNowMs,
              'updatedAtMs': writeNowMs,
              'version': 1,
            });

            tx.update(_cfgRef(leagueId), <String, dynamic>{
              'qtyRemaining': remaining - 1,
              'updatedAtMs': writeNowMs,
            });
          });

          out.add(codeId);
          break;
        } on StateError catch (e) {
          if (e.message == 'collision') continue;
          rethrow;
        }
      }
    }

    return out;
  }

  Future<CouponCodeRedeemResult> redeemWithCode({
    required BuildContext context,
    required String leagueId,
    required String leagueName,
    required String userId,
    required String code,
  }) async {
    final authUid = _auth.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) return CouponCodeRedeemResult.failed(errorMessage: 'Not signed in');

    final codeId = code.trim().toUpperCase();
    if (codeId.isEmpty) return CouponCodeRedeemResult.failed(errorMessage: 'Empty code');

    try {
      final codeRef = _codeRef(leagueId, codeId);
      final snap = await codeRef.get();
      if (!snap.exists) return CouponCodeRedeemResult.failed(errorMessage: 'Invalid code');

      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final usedBy = (data['usedBy'] as String?) ?? '';
      if (usedBy.isNotEmpty) return CouponCodeRedeemResult.failed(errorMessage: 'Code already used');

      final currency = ((data['currency'] as String?) ?? 'USD').toUpperCase();
      final expectedAmount = (data['expectedAmount'] as num?)?.toDouble() ?? 0.0;

      int paidAtMs = 0;
      String provider = 'coupon';
      String receiptId = 'CPN-CODE-FREE';

      if (expectedAmount > 0) {
        final pay = await _payment.payLeagueCharges(
          context: context,
          userId: userId,
          leagueId: leagueId,
          leagueName: leagueName,
          amountOverride: currency == 'NGN' ? '${expectedAmount.round()}' : expectedAmount.toStringAsFixed(2),
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
      }

      await _firestore.runTransaction((tx) async {
        final codeSnap = await tx.get(codeRef);
        if (!codeSnap.exists) throw StateError('invalid');

        final d = (codeSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        if (((d['usedBy'] as String?) ?? '').isNotEmpty) throw StateError('used');

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        tx.update(codeRef, <String, dynamic>{
          'usedBy': authUid,
          'usedAtMs': paidAtMs,
          'updatedAtMs': nowMs,
        });

        final rRef = _redeemRef(leagueId, authUid);
        tx.set(rRef, <String, dynamic>{
          'leagueId': leagueId,
          'userId': authUid,
          'status': 'paid',
          'provider': provider,
          'receiptId': receiptId,
          'paidAtMs': paidAtMs,
          'updatedAtMs': nowMs,
          'createdAtMs': nowMs,
          'currency': currency,
          'expectedAmount': expectedAmount,
          'code': codeId,
          'version': 1,
        });
      });

      return CouponCodeRedeemResult.success(
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        provider: provider,
        amountCharged: expectedAmount,
        currency: currency,
      );
    } catch (e) {
      return CouponCodeRedeemResult.failed(errorMessage: e.toString());
    }
  }
}
