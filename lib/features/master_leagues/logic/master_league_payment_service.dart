import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../domain/master_league_plan.dart';
import 'master_league_pricing_service.dart';

class MasterLeaguePaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  final String currency;
  final String totalAmount;

  const MasterLeaguePaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.currency,
    required this.totalAmount,
  });

  factory MasterLeaguePaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required String currency,
    required String totalAmount,
  }) {
    return MasterLeaguePaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      currency: currency,
      totalAmount: totalAmount,
    );
  }

  factory MasterLeaguePaymentResult.failed({
    required String provider,
    required String errorMessage,
    String currency = '',
    String totalAmount = '0',
  }) {
    return MasterLeaguePaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      currency: currency,
      totalAmount: totalAmount,
    );
  }
}

abstract class MasterLeaguePaymentService {
  Future<MasterLeaguePaymentResult> purchaseMasterLeagueAccess({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
  });

  String get providerName;
}

class FlutterwaveMasterLeaguePaymentService
    implements MasterLeaguePaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  Locale _effectiveLocale(BuildContext context) {
    final base = Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;

    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return Locale(
        base.languageCode.isNotEmpty ? base.languageCode : 'en',
        forced,
      );
    }
    return base;
  }

  String _paymentOptionsForCurrency(String currency) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return 'card,ussd,banktransfer';
    return 'card';
  }

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  double _roundMoney(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return v.roundToDouble();
    return double.parse(v.toStringAsFixed(2));
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

  @override
  Future<MasterLeaguePaymentResult> purchaseMasterLeagueAccess({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
  }) async {
    String currencyUsed = '';
    String totalAmount = '0';
    String attemptId = '';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      FlutterwaveConfig.assertConfigured();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }
      final authUid = currentUser.uid.trim();
      if (authUid.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }

      final pricing = MasterLeaguePricingService();
      final loc = _effectiveLocale(context);

      final price = await pricing.getMasterLeaguePriceForPlan(
        plan: plan,
        locale: loc,
      );
      if (price == null) {
        throw StateError(
          "MasterLink ${plan.displayName} price isn't configured yet. "
          "Please try again later.",
        );
      }

      currencyUsed = price.currency.trim().toUpperCase();

      final rawAmount = (price.amount is int)
          ? (price.amount as int).toDouble()
          : (price.amount as num).toDouble();
      final rounded = _roundMoney(currencyUsed, rawAmount);
      if (rounded <= 0) {
        throw StateError(
          'MasterLink price is invalid. Please contact support.',
        );
      }

      totalAmount = _toFlutterwaveAmount(rounded);
      final planLabel = 'MasterLink-${plan.displayName}';

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currencyUsed,
          amount: rounded,
          amountStr: totalAmount,
          userId: authUid,
          leagueId: '',
          leagueName: planLabel,
          items: [
            PaymentLineItem(
              productType: 'masterLink',
              productSubType: 'masterlink_${plan.id}',
              quantity: 1,
              amount: rounded,
            ),
          ],
        ),
      );

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: 'masterLink',
        leagueId: '',
        leagueName: planLabel,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final String email = (currentUser.email?.trim().isNotEmpty ?? false)
          ? currentUser.email!.trim()
          : 'user_$effectiveUserId@eleaguehub.app';
      final String phone =
          (currentUser.phoneNumber?.trim().isNotEmpty ?? false)
              ? currentUser.phoneNumber!.trim()
              : '0000000000';
      final String name = (currentUser.displayName?.trim().isNotEmpty ?? false)
          ? currentUser.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef =
          'EH-MLK-${plan.id.toUpperCase()}-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: _paymentOptionsForCurrency(currencyUsed),
        customization: Customization(
          title: 'EleagueHub',
          description: 'MasterLink ${plan.displayName} access (3 months)',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      debugPrint(
        'Flutterwave charge result: success=${response.success} '
        'status=${response.status} txRef=${response.txRef} '
        'transactionId=${response.transactionId}',
      );

      if (_isChargeSuccessful(response)) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: 'Missing transactionId.',
          );
          throw StateError(
            'Payment success returned without transactionId.',
          );
        }

        final resolvedTxRef =
            (response.txRef?.toString().trim().isNotEmpty ?? false)
                ? response.txRef!.toString().trim()
                : txRef;

        final recorded =
            await PaymentsService.instance.recordFlutterwaveClientSuccess(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'masterLink',
          leagueId: '',
          leagueName: planLabel,
          success: true,
          provider: providerName,
          currency: currencyUsed,
          amount: totalAmount,
          receiptId: recorded.receiptId,
          errorMessage: null,
          userId: effectiveUserId,
        );

        return MasterLeaguePaymentResult.paid(
          receiptId: recorded.receiptId,
          paidAtMs: recorded.paidAtMs,
          provider: providerName,
          currency: currencyUsed,
          totalAmount: totalAmount,
        );
      }

      final status = (response.status ?? '').toString().trim();
      final msg = status.isNotEmpty
          ? 'Payment not successful (status: $status)'
          : 'Payment cancelled or not successful';

      if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: msg,
        );
      }

      await AppAnalyticsService.instance.logPaymentResult(
        kind: 'masterLink',
        leagueId: '',
        leagueName: planLabel,
        success: false,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        receiptId: null,
        errorMessage: msg,
        userId: effectiveUserId,
      );

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        currency: currencyUsed,
        totalAmount: totalAmount,
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

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        currency: currencyUsed,
        totalAmount: totalAmount,
      );
    }
  }
}
