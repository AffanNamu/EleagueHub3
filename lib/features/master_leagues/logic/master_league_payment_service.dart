import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  Locale _effectiveLocale(BuildContext context) {
    // Stronger fallback than maybeLocaleOf(context) alone.
    final base = Localizations.maybeLocaleOf(context) ?? WidgetsBinding.instance.platformDispatcher.locale;

    // Respect your app’s forced-country behavior (Nigeria-first) from FlutterwaveConfig.
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return Locale(base.languageCode.isNotEmpty ? base.languageCode : 'en', forced);
    }

    return base;
  }

  String _paymentOptionsForCurrency(String currency) {
    final c = currency.trim().toUpperCase();
    // USSD/banktransfer are typically NGN flows; for USD keep it simple.
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
    if (c == 'NGN') return v.roundToDouble(); // no decimals
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
  }) async {
    String currencyUsed = '';
    String totalAmount = '0';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      FlutterwaveConfig.assertConfigured();

      final pricing = MasterLeaguePricingService();

      // Use effective locale (with forced country code support).
      final loc = _effectiveLocale(context);
      var price = await pricing.getMasterLeaguePriceForLocale(loc);

      // Extra Nigeria fallback (helps if locale comes back without a countryCode in some builds)
      final cc = (loc.countryCode ?? '').trim().toUpperCase();
      if (cc == 'NG' && price != null && price.currency.trim().toUpperCase() != 'NGN') {
        final forcedNg = Locale(loc.languageCode.isNotEmpty ? loc.languageCode : 'en', 'NG');
        final priceNg = await pricing.getMasterLeaguePriceForLocale(forcedNg);
        if (priceNg != null) price = priceNg;
      }

      if (price == null) {
        throw StateError("Master League price isn't configured yet. Please try again later.");
      }

      currencyUsed = price.currency.trim().toUpperCase();

      final rawAmount = (price.amount is int)
          ? (price.amount as int).toDouble()
          : (price.amount as num).toDouble();

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
        paymentOptions: _paymentOptionsForCurrency(currencyUsed),
        customization: Customization(
          title: 'EleagueHub',
          description: 'Master League access (3 months)',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      debugPrint(
        'Flutterwave charge result: success=${response.success} status=${response.status} '
        'txRef=${response.txRef} transactionId=${response.transactionId}',
      );

      if (_isChargeSuccessful(response)) {
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

      final status = (response.status ?? '').toString().trim();
      final msg = status.isNotEmpty ? 'Payment not successful (status: $status)' : 'Payment cancelled or not successful';

      await AppAnalyticsService.instance.logPaymentResult(
        kind: 'master_league',
        leagueId: '',
        leagueName: 'Master League',
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
