import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';

final leagueChargesPaymentServiceProvider = Provider<LeagueChargesPaymentService>((ref) {
  return FlutterwaveLeagueChargesPaymentService();
});

class LeagueChargesPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  const LeagueChargesPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
  });

  factory LeagueChargesPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
  }) {
    return LeagueChargesPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
    );
  }

  factory LeagueChargesPaymentResult.failed({
    required String provider,
    required String errorMessage,
  }) {
    return LeagueChargesPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
    );
  }
}

abstract class LeagueChargesPaymentService {
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
  });

  String get providerName;
}

class FlutterwaveLeagueChargesPaymentService implements LeagueChargesPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  @override
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
  }) async {
    try {
      FlutterwaveConfig.assertConfigured();

      final locale = Localizations.maybeLocaleOf(context);
      final pricing = FlutterwaveConfig.pricingForLocale(locale);
      FlutterwaveConfig.assertValidPricing(pricing);

      final authUser = FirebaseAuth.instance.currentUser;
      final String email = (authUser?.email?.trim().isNotEmpty ?? false)
          ? authUser!.email!.trim()
          : 'user_$userId@eleaguehub.app';
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

      final txRef = 'EH-VIEW-$leagueId-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final style = FlutterwaveStyle(
        appBarText: 'EleagueHub Payment',
        buttonColor: Colors.cyanAccent,
        appBarIcon: const Icon(Icons.arrow_back, color: Colors.white),
        buttonTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        appBarTextStyle: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        mainBackgroundColor: Colors.white,
        buttonText: 'Pay',
        dialogCancelTextStyle: const TextStyle(color: Colors.black),
        dialogContinueTextStyle: const TextStyle(color: Colors.blue),
        dialogBackgroundColor: Colors.white,
      );

      final flutterwave = Flutterwave(
        context: context,
        style: style,
        publicKey: FlutterwaveConfig.publicKey,
        currency: pricing.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: pricing.viewLeagueAmount,
        customer: customer,
        paymentOptions: 'card,ussd,banktransfer',
        customization: Customization(
          title: 'EleagueHub',
          description: 'League access charges: $leagueName',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge();

      if (response.success == true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt = (response.transactionId != null && '${response.transactionId}'.trim().isNotEmpty)
            ? 'FLW-${response.transactionId}'
            : (response.txRef?.trim().isNotEmpty ?? false)
                ? 'FLW-${response.txRef}'
                : 'FLW-$txRef';

        return LeagueChargesPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
        );
      }

      final message = (response.message?.trim().isNotEmpty ?? false) ? response.message!.trim() : 'Payment cancelled';
      return LeagueChargesPaymentResult.failed(provider: providerName, errorMessage: message);
    } catch (e) {
      return LeagueChargesPaymentResult.failed(provider: providerName, errorMessage: e.toString());
    }
  }
}
