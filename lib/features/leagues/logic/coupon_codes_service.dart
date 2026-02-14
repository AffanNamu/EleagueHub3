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
    String? customCode,
  }) async {
    final authUid = _auth.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) throw StateError('Not signed in (no Firebase UID).');

    final customRaw = (customCode ?? '').trim();
    final isCustom = customRaw.isNotEmpty;

    final effectiveCount = isCustom ? 1 : count;
    if (effectiveCount <= 0) return <String>[];

    final organizerUidForWrite =
        (organizerAuthUid != null && organizerAuthUid.trim() == authUid) ? authUid : authUid;

    // ============================================================
    // DEBUG BLOCK START — remove after fixing
    // ============================================================
    print('');
    print('========================================');
    print('=== COUPON GENERATE DEBUG ===');
    print('========================================');
    print('Auth UID: $authUid');
    print('Auth UID length: ${authUid.length}');
    print('League ID: $leagueId');
    print('Count: $effectiveCount');
    print('Is custom: $isCustom');
    print('');

    // Check league document
    try {
      final leagueSnap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .get(const GetOptions(source: Source.server));
      print('--- LEAGUE DOC ---');
      print('League exists: ${leagueSnap.exists}');
      if (leagueSnap.exists) {
        final ld = leagueSnap.data()!;
        final orgUid = ld['organizerUid'];
        final ownerUid = ld['ownerUid'];
        final orgUserId = ld['organizerUserId'];
        final ownerId = ld['ownerId'];
        print('organizerUid: "$orgUid" (type: ${orgUid.runtimeType}) match: ${orgUid == authUid}');
        print('ownerUid: "$ownerUid" (type: ${ownerUid.runtimeType}) match: ${ownerUid == authUid}');
        print('organizerUserId: "$orgUserId" (type: ${orgUserId.runtimeType}) length: ${orgUserId?.toString().length ?? 0}');
        print('ownerId: "$ownerId" (type: ${ownerId.runtimeType}) match: ${ownerId == authUid}');

        // Check all keys for any owner-like field
        final ownerKeys = ld.keys.where((k) =>
            k.toLowerCase().contains('owner') ||
            k.toLowerCase().contains('organizer') ||
            k.toLowerCase().contains('uid'));
        print('All owner-like keys: ${ownerKeys.toList()}');
        for (final k in ownerKeys) {
          print('  $k = "${ld[k]}" (${ld[k].runtimeType})');
        }
      }
    } catch (e) {
      print('League doc read error: $e');
    }

    // Check coupon config
    try {
      final cfgSnap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('couponConfig')
          .doc('config')
          .get(const GetOptions(source: Source.server));
      print('');
      print('--- COUPON CONFIG ---');
      print('Config exists: ${cfgSnap.exists}');
      if (cfgSnap.exists) {
        final cfg = cfgSnap.data()!;
        print('qtyRemaining: ${cfg['qtyRemaining']} (${cfg['qtyRemaining'].runtimeType})');
        print('qtyTotal: ${cfg['qtyTotal']} (${cfg['qtyTotal'].runtimeType})');
        print('currency: ${cfg['currency']} (${cfg['currency'].runtimeType})');
        print('discountPercent: ${cfg['discountPercent']} (${cfg['discountPercent'].runtimeType})');
        print('organizerUserId: ${cfg['organizerUserId']} (${cfg['organizerUserId'].runtimeType})');
        print('unitPrice: ${cfg['unitPrice']} (${cfg['unitPrice'].runtimeType})');
        print('effectiveUnit: ${cfg['effectiveUnit']} (${cfg['effectiveUnit'].runtimeType})');
        print('leagueId in config: ${cfg['leagueId']} match: ${cfg['leagueId'] == leagueId}');
        print('threshold: ${cfg['threshold']} (${cfg['threshold'].runtimeType})');
        print('thresholdDiscountPercent: ${cfg['thresholdDiscountPercent']} (${cfg['thresholdDiscountPercent'].runtimeType})');
        print('userPaysPercent: ${cfg['userPaysPercent']} (${cfg['userPaysPercent'].runtimeType})');
        print('organizerPaysPercent: ${cfg['organizerPaysPercent']} (${cfg['organizerPaysPercent'].runtimeType})');
        print('createdAtMs: ${cfg['createdAtMs']} (${cfg['createdAtMs'].runtimeType})');
        print('updatedAtMs: ${cfg['updatedAtMs']} (${cfg['updatedAtMs'].runtimeType})');
        print('version: ${cfg['version']} (${cfg['version'].runtimeType})');
        print('All config keys: ${cfg.keys.toList()}');
      }
    } catch (e) {
      print('Config read error: $e');
    }

    // Check pricing doc
    try {
      final pricingSnap = await _firestore
          .collection('app')
          .doc('pricing')
          .get(const GetOptions(source: Source.server));
      print('');
      print('--- PRICING DOC ---');
      print('Pricing exists: ${pricingSnap.exists}');
      if (pricingSnap.exists) {
        final p = pricingSnap.data()!;
        print('Pricing keys: ${p.keys.toList()}');
        if (p.containsKey('usd') && p['usd'] is Map) {
          final usd = (p['usd'] as Map).cast<String, dynamic>();
          print('USD accessFee: ${usd['accessFee']} (${usd['accessFee'].runtimeType})');
          print('USD couponUnit: ${usd['couponUnit']} (${usd['couponUnit'].runtimeType})');
        }
        if (p.containsKey('ngn') && p['ngn'] is Map) {
          final ngn = (p['ngn'] as Map).cast<String, dynamic>();
          print('NGN accessFee: ${ngn['accessFee']} (${ngn['accessFee'].runtimeType})');
          print('NGN couponUnit: ${ngn['couponUnit']} (${ngn['couponUnit'].runtimeType})');
        }
      }
    } catch (e) {
      print('Pricing read error: $e');
    }

    print('');
    print('========================================');
    print('=== END DEBUG — NOW ATTEMPTING GENERATE ===');
    print('========================================');
    print('');
    // ============================================================
    // DEBUG BLOCK END
    // ============================================================

    // Rules require cfgCurrent.exists for couponCodes create => ensure config exists.
    await _cfgService.ensureConfigInitializedFromLeague(leagueId);

    final List<String> out = [];

    if (isCustom) {
      final base = _sanitizeCustomBase(customRaw);

      try {
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

          final codeData = <String, dynamic>{
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
          };

          final cfgUpdateData = <String, dynamic>{
            'qtyRemaining': remaining - 1,
            'updatedAtMs': writeNowMs,
          };

          // DEBUG: Print exact write data
          print('');
          print('=== WRITING COUPON CODE (custom) ===');
          print('Doc path: leagues/$leagueId/couponCodes/$codeId');
          for (final e in codeData.entries) {
            print('  ${e.key}: ${e.value} (${e.value.runtimeType})');
          }
          print('');
          print('=== WRITING CONFIG UPDATE ===');
          print('Doc path: leagues/$leagueId/couponConfig/config');
          for (final e in cfgUpdateData.entries) {
            print('  ${e.key}: ${e.value} (${e.value.runtimeType})');
          }
          print('  current qtyRemaining: $remaining');
          print('  new qtyRemaining: ${remaining - 1}');
          print('');

          tx.set(docRef, codeData);
          tx.update(_cfgRef(leagueId), cfgUpdateData);

          out.add(codeId);
        });
      } catch (e) {
        print('');
        print('!!! CUSTOM CODE TRANSACTION FAILED !!!');
        print('Error type: ${e.runtimeType}');
        print('Error: $e');
        if (e is FirebaseException) {
          print('Firebase code: ${(e).code}');
          print('Firebase message: ${(e).message}');
          print('Firebase plugin: ${(e).plugin}');
        }
        print('');
        rethrow;
      }

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

            final codeData = <String, dynamic>{
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
            };

            final cfgUpdateData = <String, dynamic>{
              'qtyRemaining': remaining - 1,
              'updatedAtMs': writeNowMs,
            };

            // DEBUG: Print exact write data (first attempt of first code only)
            if (i == 0 && attempts == 1) {
              print('');
              print('=== WRITING COUPON CODE (random) ===');
              print('Doc path: leagues/$leagueId/couponCodes/$codeId');
              for (final e in codeData.entries) {
                print('  ${e.key}: ${e.value} (${e.value.runtimeType})');
              }
              print('');
              print('=== WRITING CONFIG UPDATE ===');
              print('Doc path: leagues/$leagueId/couponConfig/config');
              for (final e in cfgUpdateData.entries) {
                print('  ${e.key}: ${e.value} (${e.value.runtimeType})');
              }
              print('  current qtyRemaining: $remaining');
              print('  new qtyRemaining: ${remaining - 1}');
              print('');
            }

            tx.set(docRef, codeData);
            tx.update(_cfgRef(leagueId), cfgUpdateData);
          });

          out.add(codeId);
          break;
        } on StateError catch (e) {
          if (e.message == 'collision') continue;
          print('');
          print('!!! RANDOM CODE FAILED (StateError) !!!');
          print('Error: ${e.message}');
          print('');
          rethrow;
        } catch (e) {
          print('');
          print('!!! RANDOM CODE TRANSACTION FAILED !!!');
          print('Error type: ${e.runtimeType}');
          print('Error: $e');
          if (e is FirebaseException) {
            print('Firebase code: ${(e).code}');
            print('Firebase message: ${(e).message}');
            print('Firebase plugin: ${(e).plugin}');
          }
          print('');
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
