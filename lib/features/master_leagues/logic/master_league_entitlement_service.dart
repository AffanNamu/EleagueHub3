import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'master_league_payment_service.dart';

class MasterLeagueEntitlementException implements Exception {
  final String message;
  const MasterLeagueEntitlementException(this.message);

  @override
  String toString() => message;
}

/// Client-side entitlement manager (Spark plan / no Cloud Functions).
///
/// Firestore doc:
///   users/{uid}/entitlements/master_league
///
/// Rules enforce:
/// - keys().hasOnly([
///   'active','purchasedAt','expiresAtMs','lastReceiptId','lastProvider','lastPaidAtMs','updatedAtMs'
/// ])
/// - active must be true
/// - expiresAtMs must be > request.time.toMillis()
/// - on update: must NOT shorten expiresAtMs
class MasterLeagueEntitlementService {
  MasterLeagueEntitlementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const int _durationDays = 90;
  static const int _futureBufferMs = 5 * 60 * 1000; // 5 min safety

  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Please sign in and try again.',
      );
    }
    return uid;
  }

  String _uidOrEmpty() => _auth.currentUser?.uid.trim() ?? '';

  DocumentReference<Map<String, dynamic>> _docRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('entitlements')
        .doc('master_league');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  bool _isUnlockedFromData(Map<String, dynamic> data) {
    final active = data['active'] == true;
    if (!active) return false;

    if (!data.containsKey('expiresAtMs')) return true;

    final expiresAtMs = (data['expiresAtMs'] is num)
        ? (data['expiresAtMs'] as num).toInt()
        : 0;
    if (expiresAtMs <= 0) return false;

    return expiresAtMs > _nowMs();
  }

  /// Stream entitlement status.
  Stream<bool> watchUnlocked() {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return Stream<bool>.value(false);

    return _docRef(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      if (!snap.exists) return false;
      final data =
          (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _isUnlockedFromData(data);
    });
  }

  /// One-shot check. Tries server first, falls back to cache.
  Future<bool> isUnlocked() async {
    final uid = _uidOrThrow();

    try {
      final snap = await _docRef(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!snap.exists) {
        debugPrint('[Entitlement] isUnlocked: doc does not exist');
        return false;
      }
      final data =
          (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final result = _isUnlockedFromData(data);
      debugPrint(
        '[Entitlement] isUnlocked=$result active=${data['active']} '
        'expiresAtMs=${data['expiresAtMs']} now=${_nowMs()}',
      );
      return result;
    } catch (e) {
      debugPrint('[Entitlement] server check failed: $e — trying cache');
      try {
        final snap = await _docRef(uid)
            .get(const GetOptions(source: Source.cache));
        if (!snap.exists) return false;
        final data =
            (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        return _isUnlockedFromData(data);
      } catch (_) {
        return false;
      }
    }
  }

  /// Grants or extends the master league subscription after a successful payment.
  Future<void> grantOrExtendAfterPayment({
    required MasterLeaguePaymentResult payment,
  }) async {
    final uid = _uidOrThrow();

    if (!payment.success) {
      throw const MasterLeagueEntitlementException(
        'Payment not successful.',
      );
    }

    final receipt = (payment.receiptId ?? '').trim();
    if (receipt.isEmpty) {
      throw const MasterLeagueEntitlementException(
        'Missing receipt ID from payment provider.',
      );
    }

    final now = _nowMs();
    final ref = _docRef(uid);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);

        int currentExpiry = 0;
        if (snap.exists) {
          final data =
              (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
          final v = data['expiresAtMs'];
          if (v is num) currentExpiry = v.toInt();
        }

        // Extend from whichever is later: now or current expiry
        final base = (currentExpiry > now) ? currentExpiry : now;
        final extended = DateTime.fromMillisecondsSinceEpoch(base)
            .add(const Duration(days: _durationDays))
            .millisecondsSinceEpoch;

        // Add buffer so expiresAtMs > request.time.toMillis()
        final expiresAtMs = extended + _futureBufferMs;

        // Safety: never shorten
        final safeExpiresAtMs =
            (currentExpiry > 0 && expiresAtMs < currentExpiry)
                ? currentExpiry + _futureBufferMs
                : expiresAtMs;

        final payload = <String, dynamic>{
          'active': true,
          'purchasedAt': Timestamp.fromMillisecondsSinceEpoch(now),
          'expiresAtMs': safeExpiresAtMs,
          'lastReceiptId': receipt,
          'lastProvider': payment.provider,
          'lastPaidAtMs': (payment.paidAtMs > 0) ? payment.paidAtMs : now,
          'updatedAtMs': now,
        };

        debugPrint(
          '[Entitlement] Writing: uid=$uid expiresAtMs=$safeExpiresAtMs '
          'currentExpiry=$currentExpiry docExists=${snap.exists}',
        );

        // set() without merge — clean doc, exact keys only
        tx.set(ref, payload);
      }).timeout(const Duration(seconds: 20));

      debugPrint('[Entitlement] Successfully wrote entitlement for uid=$uid');

      // Verify write
      try {
        final verifySnap = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (verifySnap.exists) {
          final vData = verifySnap.data() ?? {};
          debugPrint(
            '[Entitlement] Verify: active=${vData['active']} '
            'expiresAtMs=${vData['expiresAtMs']}',
          );
        } else {
          debugPrint('[Entitlement] WARNING: doc not found after write!');
        }
      } catch (e) {
        debugPrint('[Entitlement] Verify read failed (non-critical): $e');
      }
    } on FirebaseException catch (e) {
      debugPrint(
        '[Entitlement] FirebaseException: code=${e.code} msg=${e.message}',
      );
      throw MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. "
        "Please try again. (${e.code})",
      );
    } on TimeoutException {
      throw const MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. Please try again.",
      );
    } catch (e) {
      if (e is MasterLeagueEntitlementException) rethrow;
      debugPrint('[Entitlement] Unexpected error: $e');
      throw const MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. Please try again.",
      );
    }
  }
}
