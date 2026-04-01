import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../config/backend_config.dart';
import '../app_analytics_service.dart';
import 'payment_models.dart';

class PaymentsService {
  PaymentsService._();
  static final PaymentsService instance = PaymentsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _authUidOrEmpty() => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  String _requireAuthUid() {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) {
      throw StateError('Not signed in.');
    }
    return uid;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection('payment_attempts');

  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  Future<String> createAttempt(PaymentAttemptCreate attempt) async {
    final uid = _authUidOrEmpty();
    if (uid.isEmpty) return '';

    try {
      if (attempt.userId.trim() != uid) {
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
      unawaited(
        AppAnalyticsService.instance.logEvent(
          eventName: 'payment_attempt_write_failed',
          extra: {
            'error': e.toString(),
            'provider': attempt.provider,
            'currency': attempt.currency,
            'amount': attempt.amount,
            'leagueId': attempt.leagueId,
            'leagueName': attempt.leagueName,
            'productType': attempt.productType,
            'productSubType': attempt.productSubType,
          },
        ),
      );
      return '';
    }
  }

  Future<Map<String, dynamic>?> _readAttempt(String attemptId) async {
    try {
      final snap = await _attempts.doc(attemptId).get();
      if (!snap.exists) return null;
      return (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

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

      final docUid = (existing['userId'] ?? '').toString().trim();
      if (docUid != uid) return;

      final fullDoc = _buildFullAttemptUpdate(
        existing,
        {
          'status': 'cancelled',
          'errorMessage': reason,
          'updatedAtMs': now,
        },
      );

      await _attempts
          .doc(attemptId.trim())
          .set(fullDoc, SetOptions(merge: false));
    } catch (_) {}
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

      final docUid = (existing['userId'] ?? '').toString().trim();
      if (docUid != uid) return;

      final fullDoc = _buildFullAttemptUpdate(
        existing,
        {
          'status': 'client_failed',
          'errorMessage': errorMessage,
          'updatedAtMs': now,
        },
      );

      await _attempts
          .doc(attemptId.trim())
          .set(fullDoc, SetOptions(merge: false));
    } catch (_) {}
  }

  Uri _verifyFlutterwaveUri() {
    final uri = BackendConfig.workerFlutterwaveVerifyUrl();
    if (uri != null) return uri;

    throw StateError(
      'Payment verification service is not configured. Missing EH_WORKER_BASE_URL.',
    );
  }

  Future<Map<String, dynamic>> _postJson({
    required Uri uri,
    required String idToken,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      req.add(utf8.encode(jsonEncode(body)));

      final res = await req.close().timeout(timeout);
      final raw = await res.transform(utf8.decoder).join();

      if (kDebugMode) {
        debugPrint('[PaymentsService] POST $uri -> ${res.statusCode} $raw');
      }

      Map<String, dynamic> parsed = <String, dynamic>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        parsed = <String, dynamic>{'raw': raw};
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (parsed['error'] as String?)?.trim();

        if (res.statusCode == 404) {
          throw StateError(
            'Payment verification endpoint was not found (404). '
            'Please confirm EH_WORKER_BASE_URL points to the deployed worker with /flutterwave/verify.',
          );
        }

        throw StateError(
          msg?.isNotEmpty == true
              ? msg!
              : 'Payment verification failed (${res.statusCode}).',
        );
      }

      return parsed;
    } on SocketException {
      throw StateError(
        'Network error while contacting payment verification service.',
      );
    } on TimeoutException {
      throw StateError(
        'Payment verification timed out. Please try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<PaymentVerificationResult> verifyFlutterwavePayment({
    required String attemptId,
    required String transactionId,
    required String txRef,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = _requireAuthUid();

    final safeAttemptId = attemptId.trim();
    final safeTransactionId = transactionId.trim();
    final safeTxRef = txRef.trim();

    if (safeAttemptId.isEmpty) {
      return PaymentVerificationResult.failed(
        provider: 'flutterwave',
        errorMessage: 'Missing payment attempt.',
      );
    }

    if (safeTransactionId.isEmpty) {
      return PaymentVerificationResult.failed(
        provider: 'flutterwave',
        errorMessage: 'Missing transaction id.',
      );
    }

    if (user == null) {
      return PaymentVerificationResult.failed(
        provider: 'flutterwave',
        errorMessage: 'Please sign in again and retry.',
      );
    }

    try {
      final idToken = await user.getIdToken(true);
      final safeToken = idToken?.trim() ?? '';
      if (safeToken.isEmpty) {
        return PaymentVerificationResult.failed(
          provider: 'flutterwave',
          errorMessage:
              'Unable to get authentication token. Please sign in again.',
        );
      }

      final verifyUri = _verifyFlutterwaveUri();

      if (kDebugMode) {
        debugPrint('[PaymentsService] verifyFlutterwavePayment uri=$verifyUri');
        debugPrint(
          '[PaymentsService] attemptId=$safeAttemptId txId=$safeTransactionId txRef=$safeTxRef uid=$uid',
        );
      }

      final parsed = await _postJson(
        uri: verifyUri,
        idToken: safeToken,
        body: <String, dynamic>{
          'attemptId': safeAttemptId,
          'transactionId': safeTransactionId,
          'txRef': safeTxRef,
          'userId': uid,
        },
      );

      final success = parsed['success'] == true;
      final provider = (parsed['provider'] as String? ?? 'flutterwave').trim();
      final paymentId = (parsed['paymentId'] as String? ?? '').trim();
      final receiptId = (parsed['receiptId'] as String? ?? '').trim();
      final paidAtMs = ((parsed['paidAtMs'] as num?) ?? 0).toInt();
      final status = (parsed['status'] as String? ?? '').trim();
      final currency = (parsed['currency'] as String? ?? '').trim();
      final amount = ((parsed['amount'] as num?) ?? 0).toDouble();
      final amountStr = (parsed['amountStr'] as String? ?? '').trim();
      final verifiedTxId =
          (parsed['transactionId'] as String? ?? safeTransactionId).trim();
      final verifiedTxRef = (parsed['txRef'] as String? ?? safeTxRef).trim();
      final errorMessage = (parsed['error'] as String?)?.trim();

      if (!success) {
        try {
          await markClientFailed(
            attemptId: safeAttemptId,
            errorMessage: errorMessage?.isNotEmpty == true
                ? errorMessage!
                : 'Payment verification failed.',
          );
        } catch (_) {}
      }

      return PaymentVerificationResult(
        success: success,
        provider: provider,
        paymentId: paymentId,
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        transactionId: verifiedTxId,
        txRef: verifiedTxRef,
        status: status,
        currency: currency,
        amount: amount,
        amountStr: amountStr,
        errorMessage: errorMessage,
        raw: parsed,
      );
    } catch (e) {
      try {
        await markClientFailed(
          attemptId: safeAttemptId,
          errorMessage: 'Verification failed: $e',
        );
      } catch (_) {}

      return PaymentVerificationResult.failed(
        provider: 'flutterwave',
        errorMessage: e.toString(),
        transactionId: safeTransactionId,
        txRef: safeTxRef,
      );
    }
  }

  Future<ClientRecordPaymentResult> recordFlutterwaveClientSuccess({
    required String attemptId,
    required String transactionId,
    required String txRef,
  }) async {
    final uid = _requireAuthUid();

    final now = _nowMs();
    final txId = transactionId.trim();
    if (txId.isEmpty) {
      return const ClientRecordPaymentResult(
        paymentId: '',
        receiptId: '',
        paidAtMs: 0,
      );
    }

    final paymentId = 'flutterwave_$txId';
    final receiptId = 'FLW-$txId';

    final hasAttempt = attemptId.trim().isNotEmpty;
    final attemptRef = hasAttempt ? _attempts.doc(attemptId.trim()) : null;
    final paymentRef = _payments.doc(paymentId);

    try {
      await _firestore.runTransaction((t) async {
        Map<String, dynamic> attemptData = <String, dynamic>{};

        if (attemptRef != null) {
          final attemptSnap = await t.get(attemptRef);
          if (attemptSnap.exists) {
            attemptData = (attemptSnap.data() ?? <String, dynamic>{})
                .cast<String, dynamic>();
            final attemptUid = (attemptData['userId'] ?? '').toString().trim();
            if (attemptUid != uid) {
              attemptData = <String, dynamic>{};
            }
          }
        }

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
              'leagueId': (attemptData['leagueId'] ?? '').toString(),
              'leagueName': (attemptData['leagueName'] ?? '').toString(),
              'masterLeagueId': (attemptData['masterLeagueId'] ?? '').toString(),
              'couponCode': (attemptData['couponCode'] ?? '').toString(),
              'currency': (attemptData['currency'] ?? '').toString(),
              'amount': attemptData['amount'] ?? 0,
              'amountStr': (attemptData['amountStr'] ?? '').toString(),
              'items': attemptData['items'] ?? <Map<String, dynamic>>[],
              'productType': (attemptData['productType'] ?? '').toString(),
              'productSubType': (attemptData['productSubType'] ?? '').toString(),
              'metadata': attemptData['metadata'] ?? <String, dynamic>{},
              'paidAtMs': now,
              'createdAtMs': now,
              'updatedAtMs': now,
              'verification': <String, dynamic>{
                'mode': 'client',
                'verified': false,
              },
            },
          );
        }

        if (attemptRef != null && attemptData.isNotEmpty) {
          final fullDoc = _buildFullAttemptUpdate(
            attemptData,
            {
              'status': 'client_success',
              'paymentId': paymentId,
              'receiptId': receiptId,
              'paidAtMs': now,
              'providerTransactionId': txId,
              'txRef': txRef.trim(),
              'updatedAtMs': now,
            },
          );

          t.set(attemptRef, fullDoc, SetOptions(merge: false));
        }
      });

      return ClientRecordPaymentResult(
        paymentId: paymentId,
        receiptId: receiptId,
        paidAtMs: now,
      );
    } catch (e) {
      unawaited(
        AppAnalyticsService.instance.logEvent(
          eventName: 'payment_record_write_failed',
          extra: {
            'attemptId': attemptId,
            'paymentId': paymentId,
            'txId': txId,
            'txRef': txRef,
            'error': e.toString(),
          },
        ),
      );

      return ClientRecordPaymentResult(
        paymentId: paymentId,
        receiptId: receiptId,
        paidAtMs: now,
      );
    }
  }
}
