// lib/features/leagues/logic/premium_payment_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/config/flutterwave_config.dart';
import '../../../core/config/payment_platform_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';

final premiumPaymentServiceProvider =
    Provider<PremiumPaymentService>((ref) {
  return PremiumPaymentService();
});

// ── Result ────────────────────────────────────────────────────────────────────

class PremiumPurchaseResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final int premiumDurationDays;
  final String attemptId;
  final String paymentId;
  final String transactionId;
  final String txRef;

  const PremiumPurchaseResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.premiumDurationDays,
    required this.attemptId,
    required this.paymentId,
    required this.transactionId,
    required this.txRef,
  });

  factory PremiumPurchaseResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required int premiumDurationDays,
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) =>
      PremiumPurchaseResult._(
        success: true,
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        provider: provider,
        errorMessage: null,
        premiumDurationDays: premiumDurationDays,
        attemptId: attemptId,
        paymentId: paymentId,
        transactionId: transactionId,
        txRef: txRef,
      );

  factory PremiumPurchaseResult.failed({
    required String provider,
    required String errorMessage,
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) =>
      PremiumPurchaseResult._(
        success: false,
        receiptId: null,
        paidAtMs: 0,
        provider: provider,
        errorMessage: errorMessage,
        premiumDurationDays: 0,
        attemptId: attemptId,
        paymentId: paymentId,
        transactionId: transactionId,
        txRef: txRef,
      );
}

// ── Exception ─────────────────────────────────────────────────────────────────

class PremiumActivationException implements Exception {
  final String message;
  const PremiumActivationException(this.message);

  @override
  String toString() => message;
}

// ── Service ───────────────────────────────────────────────────────────────────

class PremiumPaymentService {
  final Uuid _uuid = const Uuid();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _cleanErrorMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.contains(
        'Payment verification endpoint was not found (404)')) {
      return 'Payment verification service is not available right now. '
          'Please contact support or try again later.';
    }
    if (raw.contains('Payment verification failed (404)')) {
      return 'Payment verification service is not available right now. '
          'Please contact support or try again later.';
    }
    if (raw.contains('Bad state:')) {
      return raw.replaceFirst('Bad state:', '').trim();
    }
    if (raw.contains('SocketException')) {
      return 'Network error while verifying payment. '
          'Please check your internet and try again.';
    }
    if (raw.contains('timed out')) {
      return 'Payment verification timed out. Please try again.';
    }
    return raw;
  }

  // ── Google Play Billing path ─────────────────────────────────────────────

  Future<PremiumPurchaseResult> _purchaseViaGooglePlay({
    required String userId,
  }) async {
    final uid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return PremiumPurchaseResult.failed(
        provider: 'google_play_billing',
        errorMessage: 'Please sign in to continue.',
      );
    }

    final attemptId =
        await GooglePlayBillingService.instance.createAttempt(
      userId: uid,
      productId:
          GooglePlayBillingCatalog.premiumSubscriptionId,
      productType: 'premium_subscription',
      productSubType: 'premium_app_access',
      leagueName: 'Premium',
      metadata: <String, dynamic>{
        'premiumDurationDays': 0,
        // Duration controlled server-side by subscription period.
      },
    );

    final gpResult = await GooglePlayBillingService.instance
        .purchasePremiumSubscription(
      userId: uid,
      attemptId: attemptId,
    );

    if (!gpResult.success) {
      final msg = gpResult.errorMessage ?? 'Purchase failed.';
      if (msg.toLowerCase().contains('cancel') &&
          attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: msg,
        );
      } else if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientFailed(
          attemptId: attemptId,
          errorMessage: msg,
        );
      }
      return PremiumPurchaseResult.failed(
        provider: 'google_play_billing',
        errorMessage: msg,
        attemptId: attemptId,
        paymentId: gpResult.paymentId,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Google Play manages subscription duration server-side.
    // We use 365 as a local placeholder; the backend should
    // read the actual subscription period from the purchase token.
    return PremiumPurchaseResult.paid(
      receiptId: gpResult.orderId.isNotEmpty
          ? gpResult.orderId
          : gpResult.purchaseToken,
      paidAtMs: now,
      provider: 'google_play_billing',
      premiumDurationDays: 365,
      attemptId: attemptId,
      paymentId: gpResult.paymentId,
      transactionId: gpResult.orderId,
      txRef: gpResult.purchaseToken,
    );
  }

  // ── Flutterwave path ─────────────────────────────────────────────────────

  Future<PremiumPurchaseResult> _purchaseViaFlutterwave({
    required BuildContext context,
    required String userId,
  }) async {
    String attemptId = '';

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid.trim().isEmpty) {
        return PremiumPurchaseResult.failed(
          provider: 'flutterwave',
          errorMessage: 'Please sign in to continue.',
        );
      }

      final plan =
          await RemotePricingService.instance.getPlanForLocale(
        Localizations.maybeLocaleOf(context),
      );

      if (!plan.paymentsEnabled) {
        return PremiumPurchaseResult.failed(
          provider: 'flutterwave',
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!plan.premiumEnabled) {
        return PremiumPurchaseResult.failed(
          provider: 'flutterwave',
          errorMessage:
              'Premium is currently disabled by the administrator.',
        );
      }

      if (!plan.flutterwaveEnabled) {
        return PremiumPurchaseResult.failed(
          provider: 'flutterwave',
          errorMessage:
              'Flutterwave payments are currently unavailable.',
        );
      }

      FlutterwaveConfig.assertConfigured();

      final totalAmount = _toFlutterwaveAmount(plan.premiumFee);

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: 'flutterwave',
          currency: plan.currency,
          amount: plan.premiumFee,
          amountStr: totalAmount,
          userId: authUser.uid,
          leagueId: '',
          leagueName: 'Premium',
          productType: 'premium_subscription',
          productSubType: 'premium_app_access',
          metadata: <String, dynamic>{
            'premiumDurationDays': plan.premiumDurationDays,
          },
          items: [
            PaymentLineItem(
              productType: 'premium_subscription',
              productSubType: 'premium_app_access',
              quantity: 1,
              amount: plan.premiumFee,
            ),
          ],
        ),
      );

      try {
        await AppAnalyticsService.instance.logPaymentAttempt(
          kind: 'premium_subscription',
          leagueId: '',
          leagueName: 'Premium',
          provider: 'flutterwave',
          currency: plan.currency,
          amount: totalAmount,
          userId: userId,
        );
      } catch (_) {}

      final txRef =
          'EH-PRM-${DateTime.now().millisecondsSinceEpoch}'
          '-${_uuid.v4()}';

      final email =
          (authUser.email?.trim().isNotEmpty ?? false)
              ? authUser.email!.trim()
              : 'user_$userId@eleaguehub.app';
      final phone =
          (authUser.phoneNumber?.trim().isNotEmpty ?? false)
              ? authUser.phoneNumber!.trim()
              : '0000000000';
      final name =
          (authUser.displayName?.trim().isNotEmpty ?? false)
              ? authUser.displayName!.trim()
              : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: plan.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: plan.currency.toUpperCase() == 'NGN'
            ? 'card,ussd,banktransfer'
            : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description:
              'Premium subscription — ${plan.premiumDurationDays} days',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response =
          await flutterwave.charge(context);

      if (_isChargeSuccessful(response)) {
        final txId =
            (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          if (attemptId.isNotEmpty) {
            await PaymentsService.instance.markClientFailed(
              attemptId: attemptId,
              errorMessage: 'Missing transactionId.',
            );
          }
          return PremiumPurchaseResult.failed(
            provider: 'flutterwave',
            errorMessage: 'Missing transaction id.',
            attemptId: attemptId,
          );
        }

        final resolvedTxRef =
            (response.txRef?.trim().isNotEmpty ?? false)
                ? response.txRef!.trim()
                : txRef;

        final verification =
            await PaymentsService.instance.verifyFlutterwavePayment(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        if (!verification.success) {
          return PremiumPurchaseResult.failed(
            provider: 'flutterwave',
            errorMessage: _cleanErrorMessage(
              verification.errorMessage ??
                  'Payment verification failed.',
            ),
            attemptId: attemptId,
            paymentId: verification.paymentId,
            transactionId: txId,
            txRef: resolvedTxRef,
          );
        }

        if (BackendConfig.workerEnabled) {
          try {
            await _activatePremiumViaWorker(
              receiptId: verification.receiptId,
              transactionId: verification.transactionId,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '[PremiumPayment] Worker activation failed: $e');
            }
            return PremiumPurchaseResult.failed(
              provider: 'flutterwave',
              errorMessage:
                  'Payment verified but activation failed. '
                  'Please contact support with receipt: '
                  '${verification.receiptId}',
              attemptId: attemptId,
              paymentId: verification.paymentId,
              transactionId: verification.transactionId,
              txRef: verification.txRef,
            );
          }
        } else {
          if (kDebugMode) {
            debugPrint(
              '[PremiumPayment] WARNING: No worker configured. '
              'Using fallback premium write after verified payment.',
            );
          }
          await _writePremiumToFirestoreFallback(
            userId: userId,
            durationDays: plan.premiumDurationDays,
            receiptId: verification.receiptId,
            provider: 'flutterwave',
          );
        }

        return PremiumPurchaseResult.paid(
          receiptId: verification.receiptId,
          paidAtMs: verification.paidAtMs,
          provider: 'flutterwave',
          premiumDurationDays: plan.premiumDurationDays,
          attemptId: attemptId,
          paymentId: verification.paymentId,
          transactionId: verification.transactionId,
          txRef: verification.txRef,
        );
      }

      if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: 'Payment cancelled or not successful',
        );
      }

      return PremiumPurchaseResult.failed(
        provider: 'flutterwave',
        errorMessage: 'Payment cancelled or not successful',
        attemptId: attemptId,
      );
    } catch (e) {
      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: e.toString(),
          );
        } catch (_) {}
      }

      return PremiumPurchaseResult.failed(
        provider: 'flutterwave',
        errorMessage: _cleanErrorMessage(e),
        attemptId: attemptId,
      );
    }
  }

  // ── Public entry point ────────────────────────────────────────────────────

  Future<PremiumPurchaseResult> purchasePremium({
    required BuildContext context,
    required String userId,
  }) async {
    // Android → Google Play Billing
    if (PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling) {
      if (kDebugMode) {
        debugPrint('[PremiumPayment] Using Google Play Billing');
      }
      return _purchaseViaGooglePlay(userId: userId);
    }

    // Web / other → Flutterwave
    if (kDebugMode) {
      debugPrint('[PremiumPayment] Using Flutterwave');
    }
    return _purchaseViaFlutterwave(
        context: context, userId: userId);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  bool _isChargeSuccessful(ChargeResponse response) {
    final status =
        (response.status ?? '').toString().trim().toLowerCase();
    return response.success == true || status == 'successful';
  }

  Future<void> _activatePremiumViaWorker({
    required String receiptId,
    required String transactionId,
  }) async {
    final activateUrl = BackendConfig.premiumActivateUrl();
    if (activateUrl == null) {
      throw const PremiumActivationException(
        'Premium activation service is not configured.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PremiumActivationException(
        'Please sign in and try again.',
      );
    }

    final idToken = await user.getIdToken();
    final safeIdToken = (idToken ?? '').trim();
    if (safeIdToken.isEmpty) {
      throw const PremiumActivationException(
        'Please sign in again and try once more.',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[PremiumPayment] Activating via Worker: '
        'receiptId=$receiptId transactionId=$transactionId',
      );
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final req = await client
          .postUrl(activateUrl)
          .timeout(const Duration(seconds: 25));
      req.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer $safeIdToken');
      req.headers.set(
          HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      req.add(utf8.encode(jsonEncode(<String, dynamic>{
        'provider': 'flutterwave',
        'receiptId': receiptId,
        'transactionId': transactionId,
      })));

      final res =
          await req.close().timeout(const Duration(seconds: 25));
      final raw = await res.transform(utf8.decoder).join();

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
        throw PremiumActivationException(
          msg?.isNotEmpty == true
              ? msg!
              : 'Premium activation failed (${res.statusCode}). '
                  'Please try again.',
        );
      }

      if (kDebugMode) {
        debugPrint(
            '[PremiumPayment] Worker activation success: $parsed');
      }
    } on PremiumActivationException {
      rethrow;
    } on SocketException {
      throw const PremiumActivationException(
        'Your network appears to be offline. '
        'Please check your connection and try again.',
      );
    } on HandshakeException {
      throw const PremiumActivationException(
        'Secure connection failed. Please try again.',
      );
    } on TimeoutException {
      throw const PremiumActivationException(
        "We couldn't activate premium right now. Please try again.",
      );
    } catch (e) {
      throw PremiumActivationException(
        "We couldn't activate premium right now. "
        'Please try again. ($e)',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _writePremiumToFirestoreFallback({
    required String userId,
    required int durationDays,
    required String receiptId,
    required String provider,
  }) async {
    final expiresAt = DateTime.now()
        .add(Duration(days: durationDays))
        .millisecondsSinceEpoch;

    await _firestore
        .collection('users')
        .doc(userId)
        .set({
      'isPremium': true,
      'premiumExpiresAtMs': expiresAt,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 20));
  }
}
