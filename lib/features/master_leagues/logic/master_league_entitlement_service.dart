import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import 'master_league_firestore_paths.dart';
import 'master_league_payment_service.dart';

/// Master League premium entitlement is a SUBSCRIPTION:
/// - 3 months access
/// - renew required after expiry
///
/// Firestore path:
/// `users/{uid}/entitlements/master_league`
/// fields:
/// - active: bool
/// - purchasedAt: Timestamp
/// - expiresAtMs: int  (millisecondsSinceEpoch)
/// - lastReceiptId: string
/// - lastProvider: string
/// - lastPaidAtMs: int
/// - updatedAtMs: int
class MasterLeagueEntitlementService {
  MasterLeagueEntitlementService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const Duration accessDuration = Duration(days: 90);

  final FirebaseFirestore _firestore;

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw const MasterLeagueEntitlementException('Please sign in and try again.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _ref(String uid) {
    return _firestore
        .collection(MasterLeagueFirestorePaths.usersCollection)
        .doc(uid)
        .collection(MasterLeagueFirestorePaths.entitlementsSubcollection)
        .doc(MasterLeagueFirestorePaths.masterLeagueEntitlementId);
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  bool _isActiveAndNotExpiredFromData(Map<String, dynamic> data, int nowMs) {
    final activeRaw = data['active'];
    final active = (activeRaw is bool)
        ? activeRaw
        : (activeRaw is num)
            ? activeRaw.toInt() == 1
            : (activeRaw is String)
                ? activeRaw.trim().toLowerCase() == 'true'
                : false;

    if (!active) return false;

    final expiresAtMs = (data['expiresAtMs'] as num?)?.toInt() ?? 0;

    // Backward compatibility:
    // If expiresAtMs is missing/0 but active=true, treat as valid.
    // (Prevents locking older deployments immediately; migrate later.)
    if (expiresAtMs <= 0) return true;

    return expiresAtMs > nowMs;
  }

  Stream<bool> watchUnlocked() {
    try {
      final uid = _requireAuthUid();
      return _ref(uid).snapshots(includeMetadataChanges: true).map((snap) {
        final data = snap.data() ?? const <String, dynamic>{};
        return _isActiveAndNotExpiredFromData(data, _nowMs());
      });
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }

  Stream<int?> watchExpiresAtMs() {
    try {
      final uid = _requireAuthUid();
      return _ref(uid).snapshots(includeMetadataChanges: true).map((snap) {
        final data = snap.data() ?? const <String, dynamic>{};
        final v = (data['expiresAtMs'] as num?)?.toInt();
        return v;
      });
    } catch (_) {
      return const Stream<int?>.empty();
    }
  }

  Future<bool> isUnlocked() async {
    final uid = _requireAuthUid();
    final snap = await _ref(uid).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 12));
    final data = snap.data() ?? const <String, dynamic>{};
    return _isActiveAndNotExpiredFromData(data, _nowMs());
  }

  Future<int?> getExpiresAtMs() async {
    final uid = _requireAuthUid();
    final snap = await _ref(uid).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 12));
    final data = snap.data() ?? const <String, dynamic>{};
    final v = (data['expiresAtMs'] as num?)?.toInt();
    return v;
  }

  /// Call this ONLY after successful payment.
  ///
  /// Renewal behavior:
  /// - If user is still active and not expired, extend from existing expiry.
  /// - If expired or missing expiry, extend from now.
  Future<void> grantOrExtendAfterPayment({
    required MasterLeaguePaymentResult payment,
  }) async {
    final uid = _requireAuthUid();
    if (!payment.success) {
      throw const MasterLeagueEntitlementException('Payment not successful.');
    }

    final receiptId = (payment.receiptId ?? '').trim();
    if (receiptId.isEmpty) {
      throw const MasterLeagueEntitlementException('Missing receipt id.');
    }

    final nowMs = _nowMs();
    final durationMs = accessDuration.inMilliseconds;

    try {
      await _firestore.runTransaction((txn) async {
        final ref = _ref(uid);
        final snap = await txn.get(ref);

        int baseMs = nowMs;

        if (snap.exists) {
          final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
          final active = (data['active'] is bool) ? (data['active'] as bool) : false;
          final existingExpiry = (data['expiresAtMs'] as num?)?.toInt() ?? 0;

          if (active && existingExpiry > nowMs) {
            baseMs = existingExpiry;
          } else {
            baseMs = nowMs;
          }
        }

        final newExpiry = baseMs + durationMs;

        txn.set(
          ref,
          <String, dynamic>{
            'active': true,
            'purchasedAt': FieldValue.serverTimestamp(),
            'expiresAtMs': newExpiry,
            'lastReceiptId': receiptId,
            'lastProvider': payment.provider,
            'lastPaidAtMs': payment.paidAtMs > 0 ? payment.paidAtMs : nowMs,
            'updatedAtMs': nowMs,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 15));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const MasterLeagueEntitlementException("We couldn't update your subscription right now. Please try again.");
      }
      throw MasterLeagueEntitlementException("We couldn't update your subscription. Please try again. (${e.code})");
    } on TimeoutException {
      throw const MasterLeagueEntitlementException('Your internet connection seems unstable. Please try again.');
    }
  }
}

class MasterLeagueEntitlementException implements Exception {
  final String message;
  const MasterLeagueEntitlementException(this.message);

  @override
  String toString() => message;
}
