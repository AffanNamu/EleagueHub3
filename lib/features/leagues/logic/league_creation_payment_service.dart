import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';

final leagueCreationPaymentServiceProvider = Provider<LeagueCreationPaymentService>((ref) {
  return FlutterwaveLeagueCreationPaymentService();
});

class LeagueCreationPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  const LeagueCreationPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
  });

  factory LeagueCreationPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
  }) {
    return LeagueCreationPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
    );
  }

  factory LeagueCreationPaymentResult.failed({
    required String provider,
    required String errorMessage,
  }) {
    return LeagueCreationPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
    );
  }
}

abstract class LeagueCreationPaymentService {
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
  });

  String get providerName;
}

class FlutterwaveLeagueCreationPaymentService implements LeagueCreationPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
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

      final txRef = 'EH-CRT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: pricing.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: pricing.createLeagueAmount,
        customer: customer,
        paymentOptions: 'card,ussd,banktransfer',
        customization: Customization(
          title: 'EleagueHub',
          description: 'League creation charges: $leagueName',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      // flutterwave_standard 1.1.0 requires BuildContext in charge()
      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt = (response.transactionId != null && '${response.transactionId}'.trim().isNotEmpty)
            ? 'FLW-${response.transactionId}'
            : (response.txRef?.trim().isNotEmpty ?? false)
                ? 'FLW-${response.txRef}'
                : 'FLW-$txRef';

        return LeagueCreationPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
        );
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
      );
    } catch (e) {
      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
      );
    }
  }
}
