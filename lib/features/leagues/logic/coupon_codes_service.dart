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

  /// Normalizes a custom code so redemption is predictable:
  /// - uppercases
  /// - replaces spaces with '_'
  /// - rejects '/' because Firestore doc ids cannot contain it
  String _normalizeCustomCodeId(String raw) {
    final s = raw.trim();
    if (s.isEmpty) throw StateError('Empty custom code');
    if (s.contains('/')) throw StateError('Invalid custom code: "/" is not allowed');
    final normalized = s.replaceAll(' ', '_').toUpperCase();
    if (normalized.length < 3) throw StateError('Custom code too short');
    if (normalized.length > 80) throw StateError('Custom code too long');
    return normalized;
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  String _moneyStr(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return '${v.round()}';
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

  DocumentReference<Map<String, dynamic>> _pricingRef() => _firestore.collection('app').doc('pricing');

  int _discountPercentFromConfig(Map<String, dynamic> cfg) {
    // Preferred: discountPercent
    if (cfg.containsKey('discountPercent') && cfg['discountPercent'] is num) {
      return (cfg['discountPercent'] as num).toInt().clamp(0, 100);
    }
    // Backward compat: userPaysPercent -> discount = 100 - userPaysPercent
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

  /// Generate new one-time codes.
  ///
  /// Supports:
  /// - Random generation (count codes)
  /// - Custom-named single code (customCode)
  ///
  /// Coupon config rule:
  /// - If config is missing, we auto-initialize it safely (organizer only),
  ///   because `qtyRemaining` is mandatory and generation rules require cfgCurrent.exists.
  Future<List<String>> generateCodes({
    required String leagueId,
    String? organizerAuthUid, // call-site compat; must match auth uid
    required int count,

    /// Optional: generate a single custom-named coupon code.
    /// If provided, `count` is ignored and exactly 1 code is generated.
    String? customCode,
  }) async {
    final authUid = _auth.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      throw StateError('Not signed in (no Firebase UID).');
    }

    final String customRaw = (customCode ?? '').trim();
    final bool isCustom = customRaw.isNotEmpty;

    final int effectiveCount = isCustom ? 1 : count;
    if (effectiveCount <= 0) return <String>[];

    // Only accept organizerAuthUid if it equals authUid (prevents passing shareId).
    final organizerUidForWrite =
        (organizerAuthUid != null && organizerAuthUid.trim() == authUid) ? authUid : authUid;

    // Ensure config exists (rules require cfgCurrent.exists) before any code creation.
    // This is safe and organizer-only (as enforced by rules + service checks).
    await _cfgService.ensureConfigInitializedFromLeague(leagueId);

    final List<String> out = [];

    // Your rules enforce -1 qtyRemaining per code creation, so we do one transaction per code.
    for (int i = 0; i < effectiveCount; i++) {
      String code = '';
      int attempts = 0;

      while (true) {
        if (attempts > 10) {
          throw StateError('Could not allocate a unique code after several attempts.');
        }

        // Choose code id
        if (isCustom) {
          code = _normalizeCustomCodeId(customRaw);
        } else {
          code = 'EH${_genCode(10)}';
        }
        attempts++;

        final docRef = _codeRef(leagueId, code);

        try {
          await _firestore.runTransaction((tx) async {
            // READ config
            final cfgSnap = await tx.get(_cfgRef(leagueId));
            if (!cfgSnap.exists) throw StateError('noConfig');

            final cfg = (cfgSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
            final remaining = (cfg['qtyRemaining'] as num?)?.toInt() ?? 0;
            if (remaining <= 0) throw StateError('noRemaining');

            final discountPercent = _discountPercentFromConfig(cfg);

            // Read pricing doc so expectedAmount matches server-driven pricing.
            final pricingSnap = await tx.get(_pricingRef());
            final pricingMap = (pricingSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

            // Prefer config currency, but fallback to other if pricing missing (resilience).
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

            // Collision check
            final codeSnap = await tx.get(docRef);
            if (codeSnap.exists) {
              // Custom code collisions should surface to UI immediately.
              if (isCustom) throw StateError('customCollision');
              throw StateError('collision');
            }

            // Ensure config.updatedAtMs strictly increases (rules for manager decrement require >)
            final prevUpdatedAtMs = (cfg['updatedAtMs'] as num?)?.toInt() ?? 0;
            final wallNowMs = DateTime.now().millisecondsSinceEpoch;
            final writeNowMs = (wallNowMs > prevUpdatedAtMs) ? wallNowMs : (prevUpdatedAtMs + 1);

            // WRITE code doc
            tx.set(docRef, <String, dynamic>{
              'leagueId': leagueId,
              'organizerUserId': organizerUidForWrite, // informational
              'currency': currencyUsed,
              'discountPercent': discountPercent,
              'expectedAmount': expectedAmount,
              'usedBy': '',
              'usedAtMs': 0,
              'createdAtMs': writeNowMs,
              'updatedAtMs': writeNowMs,
              'version': 1,
            });

            // MUST decrement by exactly 1 in same transaction (rules enforce it)
            tx.update(_cfgRef(leagueId), <String, dynamic>{
              'qtyRemaining': remaining - 1,
              'updatedAtMs': writeNowMs,
            });
          });

          out.add(code);
          break;
        } on StateError catch (e) {
          if (e.message == 'collision') continue; // random collision -> retry
          rethrow;
        }
      }
    }

    return out;
  }

  /// Redeem a code:
  /// - If expectedAmount > 0 => collect payment
  /// - Atomically mark code used + create redemption doc (status=paid)
  Future<CouponCodeRedeemResult> redeemWithCode({
    required BuildContext context,
    required String leagueId,
    required String leagueName,
    required String userId, // payment metadata only; Firestore uses auth uid
    required String code,
  }) async {
    final authUid = _auth.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      return CouponCodeRedeemResult.failed(errorMessage: 'Not signed in');
    }

    final codeId = code.trim().toUpperCase();
    if (codeId.isEmpty) {
      return CouponCodeRedeemResult.failed(errorMessage: 'Empty code');
    }

    try {
      final codeRef = _codeRef(leagueId, codeId);
      final snap = await codeRef.get();
      if (!snap.exists) return CouponCodeRedeemResult.failed(errorMessage: 'Invalid code');

      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final usedBy = (data['usedBy'] as String?) ?? '';
      if (usedBy.isNotEmpty) {
        return CouponCodeRedeemResult.failed(errorMessage: 'Code already used');
      }

      final codeLeagueId = (data['leagueId'] as String?) ?? '';
      if (codeLeagueId != leagueId) {
        return CouponCodeRedeemResult.failed(errorMessage: 'Code does not belong to this league');
      }

      final currency = ((data['currency'] as String?) ?? 'USD').toUpperCase();
      final expectedAmount = (data['expectedAmount'] as num?)?.toDouble() ?? 0.0;

      int paidAtMs = 0;
      String provider = 'coupon';
      String? receiptId;

      if (expectedAmount > 0) {
        final pay = await _payment.payLeagueCharges(
          context: context,
          userId: userId,
          leagueId: leagueId,
          leagueName: leagueName,
          amountOverride: _moneyStr(currency, expectedAmount),
          couponCode: codeId,
          couponDiscountPercent: null,
          currencyOverride: currency,
        );

        if (!pay.success) {
          return CouponCodeRedeemResult.failed(
            errorMessage: pay.errorMessage ?? 'Payment failed',
            currency: currency,
          );
        }
        paidAtMs = pay.paidAtMs;
        provider = pay.provider;
        receiptId = pay.receiptId ?? 'FLW-UNKNOWN';
      } else {
        paidAtMs = DateTime.now().millisecondsSinceEpoch;
        provider = 'coupon';
        receiptId = 'CPN-CODE-FREE';
      }

      // Atomic: mark code used + create redemption paid
      await _firestore.runTransaction((tx) async {
        final codeSnap = await tx.get(codeRef);
        if (!codeSnap.exists) throw StateError('invalid');

        final d = (codeSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final wasUsed = (d['usedBy'] as String?) ?? '';
        if (wasUsed.isNotEmpty) throw StateError('used');

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        // Must be authUid to satisfy rules (usedBy == request.auth.uid)
        tx.update(codeRef, <String, dynamic>{
          'usedBy': authUid,
          'usedAtMs': paidAtMs,
          'updatedAtMs': nowMs,
        });

        // Must be docId == authUid and data.userId == authUid to satisfy rules
        final rRef = _redeemRef(leagueId, authUid);
        tx.set(rRef, <String, dynamic>{
          'leagueId': leagueId,
          'userId': authUid,
          'status': 'paid',
          'provider': provider,
          'receiptId': receiptId ?? '',
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
        receiptId: receiptId ?? 'CPN',
        paidAtMs: paidAtMs,
        provider: provider,
        amountCharged: expectedAmount,
        currency: currency,
      );
    } on StateError catch (e) {
      return CouponCodeRedeemResult.failed(errorMessage: e.message ?? 'Redemption failed');
    } catch (e) {
      return CouponCodeRedeemResult.failed(errorMessage: e.toString());
    }
  }
}
