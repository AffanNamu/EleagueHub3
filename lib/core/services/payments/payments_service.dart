import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_analytics_service.dart';
import 'payment_models.dart';

class PaymentsService {
  PaymentsService._();
  static final PaymentsService instance = PaymentsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _authUidOrEmpty() =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  String _requireAuthUid() {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) throw StateError('Not signed in.');
    return uid;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection('payment_attempts');
  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  /// BEST-EFFORT: Creates a payment attempt document.
  ///
  /// If Firestore denies the write (permission-denied) or the network fails,
  /// this returns '' and the app MUST continue (so payments never break).
  Future<String> createAttempt(PaymentAttemptCreate attempt) async {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) return '';

    try {
      if (attempt.userId.trim() != uid) {
        // Do not throw; just skip attempt logging.
        return '';
      }

      final ref = _attempts.doc();
      final now = _nowMs();

      await ref.set(
        attempt.toFirestore(attemptId: ref.id, createdAtMs: now),
        SetOptions(merge: false),
      );

      return ref.id;
    } catch (e) {
      // Never block payment flows due to analytics/logging.
      unawaited(AppAnalyticsService.instance.logEvent(
        eventName: 'payment_attempt_write_failed',
        extra: {
          'error': e.toString(),
          'provider': attempt.provider,
          'currency': attempt.currency,
          'amount': attempt.amount,
          'leagueId': attempt.leagueId,
          'leagueName': attempt.leagueName,
        },
      ));
      return '';
    }
  }

  /// Reads the full attempt document so we can rebuild it for update.
  /// Returns null on any failure.
  Future<Map<String, dynamic>?> _readAttempt(String attemptId) async {
    try {
      final snap = await _attempts.doc(attemptId).get();
      if (!snap.exists) return null;
      return (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Builds a full document for update by overlaying [changes] on [existing].
  /// Firestore rules with merge see request.resource.data as the FULL doc,
  /// so we must ensure all immutable fields are present and unchanged.
  Map<String, dynamic> _buildFullAttemptUpdate(
    Map<String, dynamic> existing,
    Map<String, dynamic> changes,
  ) {
    final full = Map<String, dynamic>.from(existing);
    full.addAll(changes);
    return full;
  }

  Future<void> markClientCancelled({
    required String attemptId,
    required String reason,
  }) async {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) return;
    if (attemptId.trim().isEmpty) return;

    final now = _nowMs();

    try {
      final existing = await _readAttempt(attemptId.trim());
      if (existing == null) return;

      // Verify ownership
      final docUid = (existing['userId'] ?? '').toString().trim();
      if (docUid != uid) return;

      final fullDoc = _buildFullAttemptUpdate(existing, {
        'status': 'cancelled',
        'errorMessage': reason,
        'updatedAtMs': now,
      });

      await _attempts.doc(attemptId.trim()).set(fullDoc, SetOptions(merge: false));
    } catch (_) {
      // best-effort
    }
  }

  Future<void> markClientFailed({
    required String attemptId,
    required String errorMessage,
  }) async {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) return;
    if (attemptId.trim().isEmpty) return;

    final now = _nowMs();

    try {
      final existing = await _readAttempt(attemptId.trim());
      if (existing == null) return;

      // Verify ownership
      final docUid = (existing['userId'] ?? '').toString().trim();
      if (docUid != uid) return;

      final fullDoc = _buildFullAttemptUpdate(existing, {
        'status': 'client_failed',
        'errorMessage': errorMessage,
        'updatedAtMs': now,
      });

      await _attempts.doc(attemptId.trim()).set(fullDoc, SetOptions(merge: false));
    } catch (_) {
      // best-effort
    }
  }

  /// Records a successful Flutterwave payment (client-side, Spark mode).
  ///
  /// IMPORTANT: This is best-effort and MUST NOT block UX.
  /// If writing to /payments or updating /payment_attempts is denied, we still return success.
  Future<ClientRecordPaymentResult> recordFlutterwaveClientSuccess({
    required String attemptId,
    required String transactionId,
    required String txRef,
  }) async {
    final uid = _requireAuthUid();

    final now = _nowMs();
    final txId = transactionId.trim();
    if (txId.isEmpty) {
      // This should be treated as failure by callers, but keep safe.
      return ClientRecordPaymentResult(
        paymentId: '',
        receiptId: '',
        paidAtMs: 0,
      );
    }

    final paymentId = 'flutterwave_$txId';
    final receiptId = 'FLW-$txId';

    final hasAttempt = attemptId.trim().isNotEmpty;
    final attemptRef =
        hasAttempt ? _attempts.doc(attemptId.trim()) : null;
    final paymentRef = _payments.doc(paymentId);

    try {
      await _firestore.runTransaction((t) async {
        Map<String, dynamic> attemptData = <String, dynamic>{};

        if (attemptRef != null) {
          final attemptSnap = await t.get(attemptRef);
          if (attemptSnap.exists) {
            attemptData = (attemptSnap.data() ?? <String, dynamic>{})
                .cast<String, dynamic>();
            final attemptUid =
                (attemptData['userId'] ?? '').toString().trim();
            // If mismatch, do not update attempt; still allow payment doc write.
            if (attemptUid != uid) {
              attemptData = <String, dynamic>{};
            }
          }
        }

        // Create payment doc if not exists (idempotent)
        final paySnap = await t.get(paymentRef);
        if (!paySnap.exists) {
          t.set(
            paymentRef,
            <String, dynamic>{
              'paymentId': paymentId,
              'attemptId': attemptId.trim(),
              'status': 'success',
              'provider': 'flutterwave',
              'providerTransactionId': txId,
              'txRef': txRef.trim(),
              'receiptId': receiptId,
              'userId': uid,
              'leagueId':
                  (attemptData['leagueId'] ?? '').toString(),
              'leagueName':
                  (attemptData['leagueName'] ?? '').toString(),
              'masterLeagueId':
                  (attemptData['masterLeagueId'] ?? '').toString(),
              'couponCode':
                  (attemptData['couponCode'] ?? '').toString(),
              'currency':
                  (attemptData['currency'] ?? '').toString(),
              'amount': attemptData['amount'] ?? 0,
              'amountStr':
                  (attemptData['amountStr'] ?? '').toString(),
              'items': attemptData['items'] ?? <Map<String, dynamic>>[],
              'paidAtMs': now,
              'createdAtMs': now,
              'verification': <String, dynamic>{
                'mode': 'client',
                'verified': false,
              },
            },
          );
        }

        // Update attempt status if we have an authorized attempt doc.
        // We must write the FULL document (not merge) so rules see all
        // immutable fields unchanged.
        if (attemptRef != null && attemptData.isNotEmpty) {
          final fullDoc = _buildFullAttemptUpdate(attemptData, {
            'status': 'client_success',
            'paymentId': paymentId,
            'receiptId': receiptId,
            'paidAtMs': now,
            'providerTransactionId': txId,
            'txRef': txRef.trim(),
            'updatedAtMs': now,
          });

          t.set(attemptRef, fullDoc);
        }
      });

      return ClientRecordPaymentResult(
        paymentId: paymentId,
        receiptId: receiptId,
        paidAtMs: now,
      );
    } catch (e) {
      // Permission denied should NEVER break purchase UX.
      unawaited(AppAnalyticsService.instance.logEvent(
        eventName: 'payment_record_write_failed',
        extra: {
          'attemptId': attemptId,
          'paymentId': paymentId,
          'txId': txId,
          'txRef': txRef,
          'error': e.toString(),
        },
      ));

      // Return success to caller so league flow continues
      return ClientRecordPaymentResult(
        paymentId: paymentId,
        receiptId: receiptId,
        paidAtMs: now,
      );
    }
  }
}
