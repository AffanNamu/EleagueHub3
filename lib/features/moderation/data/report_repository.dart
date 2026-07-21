import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class ReportRepositoryException implements Exception {
  final String message;
  const ReportRepositoryException(this.message);
  @override
  String toString() => message;
}

class ReportRepository {
  ReportRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const ReportRepositoryException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is ReportRepositoryException) throw e;
    if (e is SocketException) {
      throw const ReportRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const ReportRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        throw const ReportRepositoryException(
          'You do not have permission to submit this report.',
        );
      }
      throw const ReportRepositoryException(
        "We couldn't submit your report. Please try again.",
      );
    }
    throw const ReportRepositoryException('Something went wrong. Please try again.');
  }

  Future<void> submitReport({
    required String targetUserId,
    required String reason,
    String details = '',
  }) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();
      if (target.isEmpty || target == authUid) {
        throw const ReportRepositoryException('Invalid report target.');
      }

      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await _reports.doc(id).set(<String, dynamic>{
        'reportId': id,
        'reporterId': authUid,
        'targetUserId': target,
        'reason': reason,
        'details': details.trim(),
        'status': 'pending',
        'createdAtMs': now,
        'reviewedAtMs': 0,
        'reviewedBy': '',
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
