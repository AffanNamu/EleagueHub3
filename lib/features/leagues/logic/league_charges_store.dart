import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';

class LeagueChargesReceipt {
  final String leagueId;
  final String userId;
  final String receiptId;
  final String provider;
  final int paidAtMs;

  const LeagueChargesReceipt({
    required this.leagueId,
    required this.userId,
    required this.receiptId,
    required this.provider,
    required this.paidAtMs,
  });

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'userId': userId,
        'receiptId': receiptId,
        'provider': provider,
        'paidAtMs': paidAtMs,
      };

  factory LeagueChargesReceipt.fromMap(Map<String, dynamic> map) {
    return LeagueChargesReceipt(
      leagueId: (map['leagueId'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      receiptId: (map['receiptId'] as String?) ?? '',
      provider: (map['provider'] as String?) ?? '',
      paidAtMs: (map['paidAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// User-safe exception (picked up by UserFriendlyError mapper).
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// ONLINE-ONLY League charges store.
///
/// Source of truth is Firestore:
///   users/{uid}/leagueCharges/{leagueId}
///
/// IMPORTANT:
/// - SharedPreferences is NOT used for domain storage anymore.
/// - The legacy prefs-based constructor is kept only for compile compatibility
///   while older UI code is being migrated.
class LeagueChargesStore {
  /// Legacy constructor kept for compatibility. Preferences are not used.
  LeagueChargesStore(
    // ignore: avoid_unused_constructor_parameters
    PreferencesService prefs, {
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  LeagueChargesStore.online({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _receiptRef({
    required String userId,
    required String leagueId,
  }) {
    return _firestore.collection('users').doc(userId).collection('leagueCharges').doc(leagueId);
  }

  /// Fast check: true if a receipt doc exists for this user+league.
  ///
  /// If offline/unavailable, returns false (callers should require online before using it
  /// for payment gating).
  Future<bool> hasPaidCharges({
    required String userId,
    required String leagueId,
  }) async {
    try {
      final authUid = _requireAuthUid();
      if (authUid != userId.trim()) return false;

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final snap = await _receiptRef(userId: authUid, leagueId: leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  Future<LeagueChargesReceipt?> getReceipt({
    required String userId,
    required String leagueId,
  }) async {
    try {
      final authUid = _requireAuthUid();
      if (authUid != userId.trim()) return null;

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final snap = await _receiptRef(userId: authUid, leagueId: leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      if (!snap.exists) return null;

      final data = snap.data();
      if (data == null) return null;

      return LeagueChargesReceipt.fromMap(data);
    } catch (e) {
      throw UserFriendlyException(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  Future<void> storeReceipt(LeagueChargesReceipt receipt) async {
    try {
      final authUid = _requireAuthUid();
      if (receipt.userId.trim() != authUid) {
        throw const UserFriendlyException('You don’t have permission to do that right now.');
      }

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final ref = _receiptRef(userId: authUid, leagueId: receipt.leagueId);

      await ref
          .set(
            receipt.toMap(),
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw UserFriendlyException(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }
}
