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
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';

final premiumPaymentServiceProvider = Provider<PremiumPaymentService>((ref) {
  return PremiumPaymentService();
});

class PremiumPurchaseResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final int premiumDurationDays;

  const PremiumPurchaseResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.premiumDurationDays,
  });

  factory PremiumPurchaseResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required int premiumDurationDays,
  }) =>
      PremiumPurchaseResult._(
        success: true,
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        provider: provider,
        errorMessage: null,
        premiumDurationDays: premiumDurationDays,
      );

  factory PremiumPurchaseResult.failed({
    required String provider,
    required String errorMessage,
  }) =>
      PremiumPurchaseResult._(
        success: false,
        receiptId: null,
        paidAtMs: 0,
        provider: provider,
        errorMessage: errorMessage,
        premiumDurationDays: 0,
      );
}

class PremiumActivationException implements Exception {
  final String message;
  const PremiumActivationException(this.message);

  @override
  String toString() => message;
}

class PremiumPaymentService {
  final Uuid _uuid = const Uuid();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  Future<PremiumPurchaseResult> purchasePremium({
    required BuildContext context,
    required String userId,
  }) async {
    String attemptId = '';

    try {
      final plan = await RemotePricingService.instance
          .getPlanForLocale(Localizations.maybeLocaleOf(context));

      if (!plan.premiumEnabled) {
        // Premium disabled — grant free access via server if available,
        // otherwise fall back to client write.
        final now = DateTime.now().millisecondsSinceEpoch;
        final freeReceiptId = 'FREE-DISABLED-$now';

        if (BackendConfig.workerEnabled) {
          // Even for free, write via server to maintain consistency.
          await _writePremiumViaServer(
            userId: userId,
            durationDays: plan.premiumDurationDays,
            receiptId: freeReceiptId,
            provider: 'free',
            transactionId: '',
          );
        } else {
          await _writePremiumToFirestoreFallback(
            userId: userId,
            durationDays: plan.premiumDurationDays,
            receiptId: freeReceiptId,
            provider: 'free',
          );
        }

        return PremiumPurchaseResult.paid(
          receiptId: freeReceiptId,
          paidAtMs: now,
          provider: 'free',
          premiumDurationDays: plan.premiumDurationDays,
        );
      }

      FlutterwaveConfig.assertConfigured();

      final totalAmount = _toFlutterwaveAmount(plan.premiumFee);

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: _providerName,
          currency: plan.currency,
          amount: plan.premiumFee,
          amountStr: totalAmount,
          userId: FirebaseAuth.instance.currentUser!.uid,
          leagueId: '',
          leagueName: 'App Unlock',
          items: [
            PaymentLineItem(
              productType: 'appUnlock',
              productSubType: 'premium_subscription',
              quantity: 1,
              amount: plan.premiumFee,
            ),
          ],
        ),
      );

      try {
        await AppAnalyticsService.instance.logPaymentAttempt(
          kind: 'appUnlock',
          leagueId: '',
          leagueName: 'App Unlock',
          provider: _providerName,
          currency: plan.currency,
          amount: totalAmount,
          userId: userId,
        );
      } catch (_) {}

      final txRef =
          'EH-PRM-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final authUser = FirebaseAuth.instance.currentUser;
      final email = (authUser?.email?.trim().isNotEmpty ?? false)
          ? authUser!.email!.trim()
          : 'user_$userId@eleaguehub.app';
      final phone = (authUser?.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser!.phoneNumber!.trim()
          : '0000000000';
      final name = (authUser?.displayName?.trim().isNotEmpty ?? false)
          ? authUser!.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(name: name, phoneNumber: phone, email: email);

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

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(
              attemptId: attemptId,
              errorMessage: 'Missing transactionId.');
          return PremiumPurchaseResult.failed(
              provider: _providerName,
              errorMessage: 'Missing transaction id.');
        }

        final resolvedTxRef =
            (response.txRef?.trim().isNotEmpty ?? false)
                ? response.txRef!.trim()
                : txRef;

        // Record payment attempt
        final recorded = await PaymentsService.instance
            .recordFlutterwaveClientSuccess(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        // SERVER-SIDE VERIFICATION: Activate premium via Cloudflare Worker
        if (BackendConfig.workerEnabled) {
          try {
            await _activatePremiumViaWorker(
              receiptId: recorded.receiptId,
              transactionId: txId,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '[PremiumPayment] Worker activation failed: $e');
            }
            // If worker fails, return error — do NOT fall back to client write
            // This ensures modded APKs cannot bypass server verification
            return PremiumPurchaseResult.failed(
              provider: _providerName,
              errorMessage:
                  'Payment received but activation failed. Please contact support with receipt: ${recorded.receiptId}',
            );
          }
        } else {
          // No worker configured — fall back to client-side write
          // This is INSECURE but allows Spark plan users to function
          if (kDebugMode) {
            debugPrint(
              '[PremiumPayment] WARNING: No worker configured. '
              'Using insecure client-side premium write. '
              'Set EH_WORKER_BASE_URL to enable server verification.',
            );
          }
          await _writePremiumToFirestoreFallback(
            userId: userId,
            durationDays: plan.premiumDurationDays,
            receiptId: recorded.receiptId,
            provider: _providerName,
          );
        }

        return PremiumPurchaseResult.paid(
          receiptId: recorded.receiptId,
          paidAtMs: recorded.paidAtMs,
          provider: _providerName,
          premiumDurationDays: plan.premiumDurationDays,
        );
      }

      if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
            attemptId: attemptId,
            reason: 'Payment cancelled or not successful');
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: 'Payment cancelled or not successful',
      );
    } catch (e) {
      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(
              attemptId: attemptId, errorMessage: e.toString());
        } catch (_) {}
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: e.toString(),
      );
    }
  }

  /// Calls the Cloudflare Worker `/premium/activate` endpoint.
  /// The Worker verifies the Flutterwave transaction server-side
  /// and writes `isPremium` + `premiumExpiresAtMs` to Firestore
  /// using the service account (bypassing client rules).
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
      final req =
          await client.postUrl(activateUrl).timeout(const Duration(seconds: 25));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $safeIdToken');
      req.headers
          .set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      req.add(utf8.encode(jsonEncode(<String, dynamic>{
        'provider': 'flutterwave',
        'receiptId': receiptId,
        'transactionId': transactionId,
      })));

      final res = await req.close().timeout(const Duration(seconds: 25));
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
              : 'Premium activation failed (${res.statusCode}). Please try again.',
        );
      }

      if (kDebugMode) {
        debugPrint('[PremiumPayment] Worker activation success: $parsed');
      }
    } on PremiumActivationException {
      rethrow;
    } on SocketException {
      throw const PremiumActivationException(
        'Your network appears to be offline. Please check your connection and try again.',
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
        "We couldn't activate premium right now. Please try again. ($e)",
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Server-side premium write (for free/disabled premium).
  Future<void> _writePremiumViaServer({
    required String userId,
    required int durationDays,
    required String receiptId,
    required String provider,
    required String transactionId,
  }) async {
    try {
      await _activatePremiumViaWorker(
        receiptId: receiptId,
        transactionId: transactionId,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[PremiumPayment] Server write failed for free premium: $e');
      }
      // For free/disabled premium, fall back to client write
      await _writePremiumToFirestoreFallback(
        userId: userId,
        durationDays: durationDays,
        receiptId: receiptId,
        provider: provider,
      );
    }
  }

  /// INSECURE client-side fallback.
  /// Only used when worker is not configured (development / Spark plan without worker).
  /// When worker IS configured, this is NEVER called for paid premium.
  Future<void> _writePremiumToFirestoreFallback({
    required String userId,
    required int durationDays,
    required String receiptId,
    required String provider,
  }) async {
    final expiresAt = DateTime.now()
        .add(Duration(days: durationDays))
        .millisecondsSinceEpoch;

    await _firestore.collection('users').doc(userId).update({
      'isPremium': true,
      'premiumExpiresAtMs': expiresAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
  }
}
