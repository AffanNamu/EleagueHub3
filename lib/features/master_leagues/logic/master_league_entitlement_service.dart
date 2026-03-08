import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'master_league_payment_service.dart';

final masterLeagueEntitlementServiceProvider = Provider<MasterLeagueEntitlementService>((ref) {
  return MasterLeagueEntitlementService();
});

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
/// MUST satisfy your Firestore rules:
/// - keys().hasOnly([
///   'active','purchasedAt','expiresAtMs','lastReceiptId','lastProvider','lastPaidAtMs','updatedAtMs'
/// ])
/// - expiresAtMs must be in the future
/// - on update: must NOT shorten expiresAtMs
///
/// IMPORTANT:
/// We use a TRANSACTION to read the current expiresAtMs and always extend
/// from max(now, currentExpiresAtMs). This avoids "permission-denied" caused
/// by accidentally shortening expiry.
class MasterLeagueEntitlementService {
  MasterLeagueEntitlementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const int _durationDays = 90; // 3 months ≈ 90 days
  static const int _futureBufferMs = 2 * 60 * 1000; // 2 minutes safety

  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw const MasterLeagueEntitlementException('Please sign in and try again.');
    return uid;
  }

  String _uidOrEmpty() => _auth.currentUser?.uid.trim() ?? '';

  DocumentReference<Map<String, dynamic>> _docRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('entitlements').doc('master_league');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  bool _isUnlockedFromData(Map<String, dynamic> data) {
    final active = data['active'] == true;
    if (!active) return false;

    // Backward compatibility with your rules helper:
    // If expiresAtMs is missing but active=true, treat as active.
    if (!data.containsKey('expiresAtMs')) return true;

    final expiresAtMs = (data['expiresAtMs'] is num) ? (data['expiresAtMs'] as num).toInt() : 0;
    if (expiresAtMs <= 0) return false;

    return expiresAtMs > _nowMs();
  }

  /// Stream entitlement status (used by master_leagues_providers.dart).
  Stream<bool> watchUnlocked() {
    final uid = _uidOrEmpty();
    if (uid.isEmpty) return Stream<bool>.value(false);

    return _docRef(uid).snapshots(includeMetadataChanges: true).map((snap) {
      if (!snap.exists) return false;
      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _isUnlockedFromData(data);
    });
  }

  Future<bool> isUnlocked() async {
    final uid = _uidOrThrow();

    final snap = await _docRef(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) return false;
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _isUnlockedFromData(data);
  }

  Future<void> grantOrExtendAfterPayment({
    required MasterLeaguePaymentResult payment,
  }) async {
    final uid = _uidOrThrow();

    if (!payment.success) {
      throw const MasterLeagueEntitlementException('Payment not successful.');
    }

    final receipt = (payment.receiptId ?? '').trim();
    if (receipt.isEmpty) {
      throw const MasterLeagueEntitlementException('Missing receipt ID from payment provider.');
    }

    final now = _nowMs();
    final ref = _docRef(uid);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);

        int currentExpiry = 0;
        if (snap.exists) {
          final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
          final v = data['expiresAtMs'];
          if (v is num) currentExpiry = v.toInt();
        }

        final base = (currentExpiry > now) ? currentExpiry : now;
        final extended = DateTime.fromMillisecondsSinceEpoch(base)
            .add(const Duration(days: _durationDays))
            .millisecondsSinceEpoch;

        // Must be strictly > request.time.toMillis() in rules.
        final expiresAtMs = extended + _futureBufferMs;

        // EXACT keys only (rules)
        final payload = <String, dynamic>{
          'active': true,
          'purchasedAt': Timestamp.fromMillisecondsSinceEpoch(now),
          'expiresAtMs': expiresAtMs,
          'lastReceiptId': receipt,
          'lastProvider': payment.provider,
          'lastPaidAtMs': (payment.paidAtMs > 0) ? payment.paidAtMs : now,
          'updatedAtMs': now,
        };

        // Overwrite doc (not merge) so no legacy keys remain.
        tx.set(ref, payload);
      }).timeout(const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      // This is exactly what you're seeing.
      throw MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. Please try again. (${e.code})",
      );
    } on TimeoutException {
      throw const MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. Please try again.",
      );
    } catch (_) {
      throw const MasterLeagueEntitlementException(
        "We couldn't update your subscription right now. Please try again.",
      );
    }
  }
}
