import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_analytics_service.dart';
import 'payment_models.dart';

class PaymentsService {
  PaymentsService._();
  static final PaymentsService instance = PaymentsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw StateError('Not signed in.');
    return uid;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  CollectionReference<Map<String, dynamic>> get _attempts => _firestore.collection('payment_attempts');
  CollectionReference<Map<String, dynamic>> get _payments => _firestore.collection('payments');

  Future<String> createAttempt(PaymentAttemptCreate attempt) async {
    final uid = _requireAuthUid();
    if (attempt.userId.trim() != uid) {
      throw StateError('Invalid attempt userId (must match auth uid).');
    }

    final ref = _attempts.doc();
    final now = _nowMs();

    await ref.set(
      attempt.toFirestore(attemptId: ref.id, createdAtMs: now),
      SetOptions(merge: false),
    );

    return ref.id;
  }

  Future<void> markClientCancelled({
    required String attemptId,
    required String reason,
  }) async {
    final uid = _requireAuthUid();
    final now = _nowMs();

    await _attempts.doc(attemptId).set({
      'userId': uid,
      'status': 'cancelled',
      'errorMessage': reason,
      'updatedAtMs': now,
    }, SetOptions(merge: true));

    unawaited(AppAnalyticsService.instance.logEvent(
      eventName: 'payment_attempt_cancelled',
      extra: {'attemptId': attemptId, 'reason': reason},
    ));
  }

  Future<void> markClientFailed({
    required String attemptId,
    required String errorMessage,
  }) async {
    final uid = _requireAuthUid();
    final now = _nowMs();

    await _attempts.doc(attemptId).set({
      'userId': uid,
      'status': 'client_failed',
      'errorMessage': errorMessage,
      'updatedAtMs': now,
    }, SetOptions(merge: true));

    unawaited(AppAnalyticsService.instance.logEvent(
      eventName: 'payment_attempt_failed',
      extra: {'attemptId': attemptId, 'error': errorMessage},
    ));
  }

  /// Records a successful Flutterwave payment (client-side; not server-verified).
  ///
  /// - Creates a /payments/{paymentId} document (idempotent by transactionId).
  /// - Updates /payment_attempts/{attemptId} status to client_success.
  ///
  /// You can later upgrade to server verification by replacing this with a Cloud Function call.
  Future<ClientRecordPaymentResult> recordFlutterwaveClientSuccess({
    required String attemptId,
    required String transactionId,
    required String txRef,
  }) async {
    final uid = _requireAuthUid();
    final now = _nowMs();

    final txId = transactionId.trim();
    if (txId.isEmpty) throw StateError('Missing Flutterwave transactionId');

    final paymentId = 'flutterwave_$txId';
    final receiptId = 'FLW-$txId';

    final attemptRef = _attempts.doc(attemptId);
    final paymentRef = _payments.doc(paymentId);

    await _firestore.runTransaction((t) async {
      final attemptSnap = await t.get(attemptRef);
      if (!attemptSnap.exists) {
        throw StateError('Payment attempt not found.');
      }

      final attempt = (attemptSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final attemptUid = (attempt['userId'] ?? '').toString().trim();
      if (attemptUid != uid) {
        throw StateError('Not authorized for this attempt.');
      }

      // Create payment doc (idempotent)
      final paySnap = await t.get(paymentRef);
      if (!paySnap.exists) {
        t.set(paymentRef, <String, dynamic>{
          'paymentId': paymentId,
          'attemptId': attemptId,
          'status': 'success',
          'provider': 'flutterwave',
          'providerTransactionId': txId,
          'txRef': txRef.trim(),
          'receiptId': receiptId,
          'userId': uid,

          'leagueId': (attempt['leagueId'] ?? '').toString(),
          'leagueName': (attempt['leagueName'] ?? '').toString(),
          'masterLeagueId': (attempt['masterLeagueId'] ?? '').toString(),
          'couponCode': (attempt['couponCode'] ?? '').toString(),

          'currency': (attempt['currency'] ?? '').toString(),
          'amount': attempt['amount'] ?? 0,
          'amountStr': (attempt['amountStr'] ?? '').toString(),
          'items': attempt['items'] ?? [],

          'paidAtMs': now,
          'createdAtMs': now,

          'verification': <String, dynamic>{
            'mode': 'client',
            'verified': false,
          },
        });
      }

      // Update attempt status
      t.set(attemptRef, <String, dynamic>{
        'status': 'client_success',
        'paymentId': paymentId,
        'receiptId': receiptId,
        'paidAtMs': now,
        'providerTransactionId': txId,
        'txRef': txRef.trim(),
        'updatedAtMs': now,
      }, SetOptions(merge: true));
    });

    unawaited(AppAnalyticsService.instance.logEvent(
      eventName: 'payment_client_recorded',
      extra: {
        'attemptId': attemptId,
        'paymentId': paymentId,
        'transactionId': txId,
        'txRef': txRef,
      },
    ));

    return ClientRecordPaymentResult(paymentId: paymentId, receiptId: receiptId, paidAtMs: now);
  }
}
