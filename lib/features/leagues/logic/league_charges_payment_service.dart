import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import 'league_charges_store.dart';

final leagueChargesPaymentServiceProvider =
    Provider<LeagueChargesPaymentService>((ref) {
  return FlutterwaveLeagueChargesPaymentService();
});

class LeagueChargesPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final String totalAmount;
  final String attemptId;
  final String paymentId;
  final String transactionId;
  final String txRef;

  const LeagueChargesPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.totalAmount,
    required this.attemptId,
    required this.paymentId,
    required this.transactionId,
    required this.txRef,
  });

  factory LeagueChargesPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required String totalAmount,
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return LeagueChargesPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }

  factory LeagueChargesPaymentResult.failed({
    required String provider,
    required String errorMessage,
    String totalAmount = '0',
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return LeagueChargesPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }
}

abstract class LeagueChargesPaymentService {
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
    String? amountOverride,
    String? couponCode,
    int? couponDiscountPercent,
    String? currencyOverride,
  });

  String get providerName;
}

class FlutterwaveLeagueChargesPaymentService
    implements LeagueChargesPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  String _normalizeAmount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '0';

    final d = double.tryParse(trimmed);
    if (d == null) return '0';
    if (d <= 0) return '0';

    return _toFlutterwaveAmount(d);
  }

  String _resolvedCurrency({
    required String planCurrency,
    String? override,
  }) {
    final o = (override ?? '').trim().toUpperCase();
    if (o == 'NGN' || o == 'USD') return o;
    return planCurrency;
  }

  String _resolveEffectiveUserId(String userId) {
    final u = userId.trim();
    if (u.isNotEmpty) return u;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isNotEmpty) return authUid.trim();
    return 'anonymous';
  }

  bool _isChargeSuccessful(ChargeResponse response) {
    final status = (response.status ?? '').toString().trim().toLowerCase();
    return response.success == true || status == 'successful';
  }

  String _cleanErrorMessage(Object error) {
    final raw = error.toString().trim();

    if (raw.contains('Payment verification endpoint was not found (404)')) {
      return 'Payment verification service is not available right now. Please contact support or try again later.';
    }
    if (raw.contains('Payment verification failed (404)')) {
      return 'Payment verification service is not available right now. Please contact support or try again later.';
    }
    if (raw.contains('Bad state:')) {
      return raw.replaceFirst('Bad state:', '').trim();
    }
    if (raw.contains('SocketException')) {
      return 'Network error while verifying payment. Please check your internet and try again.';
    }
    if (raw.contains('timed out')) {
      return 'Payment verification timed out. Please try again.';
    }
    return raw;
  }

  @override
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
    String? amountOverride,
    String? couponCode,
    int? couponDiscountPercent,
    String? currencyOverride,
  }) async {
    String currencyUsed = '';
    String totalAmount = '0';
    String attemptId = '';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid.trim().isEmpty) {
        return LeagueChargesPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }

      final plan = await RemotePricingService.instance.getPlanForLocale(
        Localizations.maybeLocaleOf(context),
      );

      if (!plan.paymentsEnabled) {
        return LeagueChargesPaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!plan.flutterwaveEnabled) {
        return LeagueChargesPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Flutterwave payments are currently unavailable.',
        );
      }

      FlutterwaveConfig.assertConfigured();

      currencyUsed = _resolvedCurrency(
        planCurrency: plan.currency,
        override: currencyOverride,
      );

      final defaultAmount = _toFlutterwaveAmount(plan.accessFee);
      final overrideNormalized =
          (amountOverride != null && amountOverride.trim().isNotEmpty)
              ? _normalizeAmount(amountOverride)
              : '';
      totalAmount = (overrideNormalized.isNotEmpty && overrideNormalized != '0')
          ? overrideNormalized
          : defaultAmount;

      final cpn = (couponCode ?? '').trim().toUpperCase();
      final kind = cpn.isNotEmpty ? 'coupon_redemption' : 'league_access';
      final numericAmount = double.tryParse(totalAmount) ?? 0.0;

      if (numericAmount <= 0) {
        return LeagueChargesPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Invalid payment amount.',
          totalAmount: totalAmount,
        );
      }

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currencyUsed,
          amount: numericAmount,
          amountStr: totalAmount,
          userId: authUser.uid,
          leagueId: leagueId,
          leagueName: leagueName,
          couponCode: cpn,
          productType: cpn.isNotEmpty ? 'coupon_redemption' : 'league_access',
          productSubType: cpn.isNotEmpty
              ? 'league_coupon_access'
              : 'league_standard_access',
          metadata: <String, dynamic>{
            'couponCode': cpn,
            'couponDiscountPercent': couponDiscountPercent ?? 0,
          },
          items: [
            PaymentLineItem(
              productType: 'league_access',
              productSubType: kind,
              quantity: 1,
              amount: numericAmount,
            ),
          ],
        ),
      );

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: kind,
        leagueId: leagueId,
        leagueName: leagueName,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final String email = (authUser.email?.trim().isNotEmpty ?? false)
          ? authUser.email!.trim()
          : 'user_$effectiveUserId@eleaguehub.app';
      final String phone = (authUser.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser.phoneNumber!.trim()
          : '0000000000';
      final String name = (authUser.displayName?.trim().isNotEmpty ?? false)
          ? authUser.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef =
          'EH-CHG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: currencyUsed.toUpperCase() == 'NGN'
            ? 'card,ussd,banktransfer'
            : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description: 'League charges: $leagueName',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (_isChargeSuccessful(response)) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          if (attemptId.isNotEmpty) {
            await PaymentsService.instance.markClientFailed(
              attemptId: attemptId,
              errorMessage: 'Missing transactionId.',
            );
          }
          return LeagueChargesPaymentResult.failed(
            provider: providerName,
            errorMessage: 'Missing transaction id.',
            totalAmount: totalAmount,
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
          return LeagueChargesPaymentResult.failed(
            provider: providerName,
            errorMessage: _cleanErrorMessage(
              verification.errorMessage ?? 'Payment verification failed.',
            ),
            totalAmount: totalAmount,
            attemptId: attemptId,
            paymentId: verification.paymentId,
            transactionId: txId,
            txRef: resolvedTxRef,
          );
        }

        try {
          await LeagueChargesStore.online().storeReceipt(
            LeagueChargesReceipt(
              leagueId: leagueId,
              userId: authUser.uid,
              receiptId: verification.receiptId,
              provider: providerName,
              paidAtMs: verification.paidAtMs,
            ),
          );
        } catch (_) {}

        return LeagueChargesPaymentResult.paid(
          receiptId: verification.receiptId,
          paidAtMs: verification.paidAtMs,
          provider: providerName,
          totalAmount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
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

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        totalAmount: totalAmount,
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

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
        totalAmount: totalAmount,
        attemptId: attemptId,
      );
    }
  }
}
