import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import 'master_league_pricing_service.dart';

final masterLeaguePaymentServiceProvider = Provider<MasterLeaguePaymentService>((ref) {
  return FlutterwaveMasterLeaguePaymentService();
});

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
  /// Collects the Master League subscription fee (3 months access).
  Future<MasterLeaguePaymentResult> purchaseMasterLeagueAccess({
    required BuildContext context,
    required String userId,
  });

  String get providerName;
}

class FlutterwaveMasterLeaguePaymentService implements MasterLeaguePaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

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

  @override
  Future<MasterLeaguePaymentResult> purchaseMasterLeagueAccess({
    required BuildContext context,
    required String userId,
  }) async {
    String currencyUsed = '';
    String totalAmount = '0';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      FlutterwaveConfig.assertConfigured();

      final price = await MasterLeaguePricingService().getMasterLeaguePriceForLocale(
        Localizations.maybeLocaleOf(context),
      );

      if (price == null) {
        throw StateError("Master League price isn't configured yet. Please try again later.");
      }

      currencyUsed = price.currency.trim().toUpperCase();
      final rawAmount = (price.amount is int) ? (price.amount as int).toDouble() : (price.amount as num).toDouble();

      final rounded = _roundMoney(currencyUsed, rawAmount);
      if (rounded <= 0) {
        throw StateError("Master League price is invalid. Please contact support.");
      }

      totalAmount = _toFlutterwaveAmount(rounded);

      // Analytics attempt (best-effort)
      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: 'master_league',
        leagueId: '',
        leagueName: 'Master League',
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final authUser = FirebaseAuth.instance.currentUser;

      final String email = (authUser?.email?.trim().isNotEmpty ?? false)
          ? authUser!.email!.trim()
          : 'user_$effectiveUserId@eleaguehub.app';
      final String phone = (authUser?.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser!.phoneNumber!.trim()
          : '0000000000';
      final String name = (authUser?.displayName?.trim().isNotEmpty ?? false)
          ? authUser!.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef = 'EH-MLG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: 'card,ussd,banktransfer',

        // FIX: Customization() is not const in flutterwave_standard, so don't use `const`.
        customization: Customization(
          title: 'EleagueHub',
          description: 'Master League access (3 months)',
        ),

        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt = (response.transactionId != null && '${response.transactionId}'.trim().isNotEmpty)
            ? 'FLW-${response.transactionId}'
            : (response.txRef?.trim().isNotEmpty ?? false)
                ? 'FLW-${response.txRef}'
                : 'FLW-$txRef';

        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'master_league',
          leagueId: '',
          leagueName: 'Master League',
          success: true,
          provider: providerName,
          currency: currencyUsed,
          amount: totalAmount,
          receiptId: receipt,
          errorMessage: null,
          userId: effectiveUserId,
        );

        return MasterLeaguePaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
          currency: currencyUsed,
          totalAmount: totalAmount,
        );
      }

      await AppAnalyticsService.instance.logPaymentResult(
        kind: 'master_league',
        leagueId: '',
        leagueName: 'Master League',
        success: false,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        receiptId: null,
        errorMessage: 'Payment cancelled or not successful',
        userId: effectiveUserId,
      );

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        currency: currencyUsed,
        totalAmount: totalAmount,
      );
    } catch (e) {
      try {
        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'master_league',
          leagueId: '',
          leagueName: 'Master League',
          success: false,
          provider: providerName,
          currency: currencyUsed,
          amount: totalAmount,
          receiptId: null,
          errorMessage: e.toString(),
          userId: effectiveUserId,
        );
      } catch (_) {
        // best-effort
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
