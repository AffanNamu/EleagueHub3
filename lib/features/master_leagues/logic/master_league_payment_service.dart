import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../domain/master_league.dart';
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
  final String attemptId;
  final String paymentId;
  final String transactionId;
  final String txRef;

  const MasterLeaguePaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.currency,
    required this.totalAmount,
    required this.attemptId,
    required this.paymentId,
    required this.transactionId,
    required this.txRef,
  });

  factory MasterLeaguePaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required String currency,
    required String totalAmount,
    required String attemptId,
    required String paymentId,
    required String transactionId,
    required String txRef,
  }) {
    return MasterLeaguePaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      currency: currency,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }

  factory MasterLeaguePaymentResult.failed({
    required String provider,
    required String errorMessage,
    String currency = '',
    String totalAmount = '0',
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return MasterLeaguePaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      currency: currency,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }
}

abstract class MasterLeaguePaymentService {
  Future<MasterLeaguePaymentResult> payForMasterLeagueCreation({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
    required String masterLeagueName,
    required MasterLeagueCompetitionDraft competition,
  });

  Future<MasterLeaguePaymentResult> payForOrganizerVerification({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  });

  Future<MasterLeaguePaymentResult> payForOrganizerVerificationRenewal({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
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

  Future<MasterLeaguePaymentResult> _runPayment({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
    required String productType,
    required String productSubType,
    required Map<String, dynamic> metadata,
    required List<PaymentLineItem> items,
    required String txRefPrefix,
    required String description,
    required double amount,
    required String currency,
    required String analyticsKind,
  }) async {
    String attemptId = '';
    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
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

      FlutterwaveConfig.assertConfigured();

      final rounded = _roundMoney(currency, amount);
      if (rounded <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Payment amount is invalid.',
          currency: currency,
        );
      }

      final totalAmount = _toFlutterwaveAmount(rounded);
      final safeLeagueName = leagueName.trim();

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currency,
          amount: rounded,
          amountStr: totalAmount,
          userId: authUid,
          leagueId: leagueId,
          leagueName: safeLeagueName,
          masterLeagueId: leagueId,
          productType: productType,
          productSubType: productSubType,
          metadata: metadata,
          items: items,
        ),
      );

      if (attemptId.trim().isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Unable to start payment. Please try again.',
          currency: currency,
          totalAmount: totalAmount,
        );
      }

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: safeLeagueName,
        provider: providerName,
        currency: currency,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final String email = (currentUser.email?.trim().isNotEmpty ?? false)
          ? currentUser.email!.trim()
          : 'user_$effectiveUserId@eleaguehub.app';
      final String phone = (currentUser.phoneNumber?.trim().isNotEmpty ?? false)
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
          '$txRefPrefix-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: _paymentOptionsForCurrency(currency),
        customization: Customization(
          title: 'EleagueHub',
          description: description,
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] charge result: success=${response.success} '
          'status=${response.status} txRef=${response.txRef} '
          'transactionId=${response.transactionId}',
        );
      }

      if (_isChargeSuccessful(response)) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: 'Missing transactionId.',
          );
          return MasterLeaguePaymentResult.failed(
            provider: providerName,
            errorMessage: 'Payment success returned without transaction id.',
            currency: currency,
            totalAmount: totalAmount,
            attemptId: attemptId,
          );
        }

        final resolvedTxRef =
            (response.txRef?.toString().trim().isNotEmpty ?? false)
                ? response.txRef!.toString().trim()
                : txRef;

        final verification =
            await PaymentsService.instance.verifyFlutterwavePayment(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        if (!verification.success) {
          final cleanError = _cleanErrorMessage(
            verification.errorMessage ?? 'Payment verification failed.',
          );

          await AppAnalyticsService.instance.logPaymentResult(
            kind: analyticsKind,
            leagueId: leagueId,
            leagueName: safeLeagueName,
            success: false,
            provider: providerName,
            currency: currency,
            amount: totalAmount,
            receiptId: null,
            errorMessage: cleanError,
            userId: effectiveUserId,
          );

          return MasterLeaguePaymentResult.failed(
            provider: providerName,
            errorMessage: cleanError,
            currency: currency,
            totalAmount: totalAmount,
            attemptId: attemptId,
            paymentId: verification.paymentId,
            transactionId: txId,
            txRef: resolvedTxRef,
          );
        }

        await AppAnalyticsService.instance.logPaymentResult(
          kind: analyticsKind,
          leagueId: leagueId,
          leagueName: safeLeagueName,
          success: true,
          provider: providerName,
          currency: verification.currency.isNotEmpty
              ? verification.currency
              : currency,
          amount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          receiptId: verification.receiptId,
          errorMessage: null,
          userId: effectiveUserId,
        );

        return MasterLeaguePaymentResult.paid(
          receiptId: verification.receiptId,
          paidAtMs: verification.paidAtMs,
          provider: verification.provider,
          currency: verification.currency.isNotEmpty
              ? verification.currency
              : currency,
          totalAmount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          attemptId: attemptId,
          paymentId: verification.paymentId,
          transactionId: verification.transactionId,
          txRef: verification.txRef,
        );
      }

      final status = (response.status ?? '').toString().trim().toLowerCase();
      final msg = status == 'cancelled' || status == 'cancel'
          ? 'Payment was cancelled.'
          : status.isNotEmpty
              ? 'Payment not successful (status: $status).'
              : 'Payment cancelled or not successful.';

      await PaymentsService.instance.markClientCancelled(
        attemptId: attemptId,
        reason: msg,
      );

      await AppAnalyticsService.instance.logPaymentResult(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: safeLeagueName,
        success: false,
        provider: providerName,
        currency: currency,
        amount: totalAmount,
        receiptId: null,
        errorMessage: msg,
        userId: effectiveUserId,
      );

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        currency: currency,
        totalAmount: totalAmount,
        attemptId: attemptId,
      );
    } catch (e) {
      final cleanError = _cleanErrorMessage(e);

      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: cleanError,
          );
        } catch (_) {}
      }

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: cleanError,
        currency: currency,
        attemptId: attemptId,
      );
    }
  }

  @override
  Future<MasterLeaguePaymentResult> payForMasterLeagueCreation({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
    required String masterLeagueName,
    required MasterLeagueCompetitionDraft competition,
  }) async {
    try {
      final trimmedMasterLeagueName = masterLeagueName.trim();
      final trimmedCompetitionName = competition.name.trim();

      if (trimmedMasterLeagueName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please enter a Master League name.',
        );
      }
      if (trimmedCompetitionName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please enter a competition name.',
        );
      }
      if (competition.maxParticipants < 2) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Max participants must be at least 2.',
        );
      }
      if (competition.entryFee < 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Entry fee cannot be negative.',
        );
      }

      final remotePlan = await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Flutterwave payments are currently unavailable.',
        );
      }

      final pricing = MasterLeaguePricingService();
      final loc = _effectiveLocale(context);

      final price = await pricing.getMasterLeaguePriceForPlan(
        plan: plan,
        locale: loc,
      );

      if (price == null) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              "${plan.displayName} price isn't configured yet. Please try again later.",
        );
      }

      final currencyUsed = price.currency.trim().toUpperCase();
      final rawAmount = (price.amount is int)
          ? (price.amount as int).toDouble()
          : (price.amount as num).toDouble();

      return _runPayment(
        context: context,
        userId: userId,
        leagueId: '',
        leagueName: trimmedMasterLeagueName,
        productType: 'master_league_creation',
        productSubType: 'master_league_${plan.id}',
        metadata: <String, dynamic>{
          'masterLeagueName': trimmedMasterLeagueName,
          'competitionName': trimmedCompetitionName,
          'competitionEntryFee': competition.entryFee,
          'competitionMaxParticipants': competition.maxParticipants,
          'competitionCurrency':
              competition.currency.trim().toUpperCase().isNotEmpty
                  ? competition.currency.trim().toUpperCase()
                  : currencyUsed,
          'plan': plan.id,
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'master_league_creation',
            productSubType: 'master_league_${plan.id}',
            quantity: 1,
            amount: rawAmount,
          ),
        ],
        txRefPrefix: 'EH-ML-${plan.id.toUpperCase()}',
        description: 'Create $trimmedMasterLeagueName (${plan.displayName})',
        amount: rawAmount,
        currency: currencyUsed,
        analyticsKind: 'master_league_creation',
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }

  @override
  Future<MasterLeaguePaymentResult> payForOrganizerVerification({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    try {
      final safeMasterLeagueId = masterLeagueId.trim();
      final safeMasterLeagueName = masterLeagueName.trim();

      if (safeMasterLeagueId.isEmpty || safeMasterLeagueName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Master League information is missing.',
        );
      }

      final remotePlan = await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Flutterwave payments are currently unavailable.',
        );
      }

      if (!remotePlan.organizerVerificationEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Organizer verification is currently disabled.',
        );
      }

      final fee = remotePlan.organizerVerificationFee;
      if (fee <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Organizer verification price is not configured correctly.',
        );
      }

      final currencyUsed = remotePlan.currency.trim().toUpperCase();

      return _runPayment(
        context: context,
        userId: userId,
        leagueId: safeMasterLeagueId,
        leagueName: safeMasterLeagueName,
        productType: 'organizer_verification',
        productSubType: 'master_league_organizer_verification',
        metadata: <String, dynamic>{
          'masterLeagueId': safeMasterLeagueId,
          'masterLeagueName': safeMasterLeagueName,
          'verificationMode': 'initial',
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'organizer_verification',
            productSubType: 'master_league_organizer_verification',
            quantity: 1,
            amount: fee,
          ),
        ],
        txRefPrefix: 'EH-ORGV',
        description: 'Organizer verification: $safeMasterLeagueName',
        amount: fee,
        currency: currencyUsed,
        analyticsKind: 'organizer_verification',
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }

  @override
  Future<MasterLeaguePaymentResult> payForOrganizerVerificationRenewal({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    try {
      final safeMasterLeagueId = masterLeagueId.trim();
      final safeMasterLeagueName = masterLeagueName.trim();

      if (safeMasterLeagueId.isEmpty || safeMasterLeagueName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Master League information is missing.',
        );
      }

      final remotePlan = await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Flutterwave payments are currently unavailable.',
        );
      }

      if (!remotePlan.organizerVerificationRenewalEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Verification renewal is currently disabled.',
        );
      }

      final fee = remotePlan.organizerVerificationRenewalFee;
      if (fee <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Verification renewal price is not configured correctly.',
        );
      }

      final currencyUsed = remotePlan.currency.trim().toUpperCase();

      return _runPayment(
        context: context,
        userId: userId,
        leagueId: safeMasterLeagueId,
        leagueName: safeMasterLeagueName,
        productType: 'organizer_verification_renewal',
        productSubType: 'master_league_organizer_verification_renewal',
        metadata: <String, dynamic>{
          'masterLeagueId': safeMasterLeagueId,
          'masterLeagueName': safeMasterLeagueName,
          'verificationMode': 'renewal',
          'verificationDurationDays':
              remotePlan.organizerVerificationDurationDays,
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'organizer_verification_renewal',
            productSubType: 'master_league_organizer_verification_renewal',
            quantity: 1,
            amount: fee,
          ),
        ],
        txRefPrefix: 'EH-ORGR',
        description: 'Verification renewal: $safeMasterLeagueName',
        amount: fee,
        currency: currencyUsed,
        analyticsKind: 'organizer_verification_renewal',
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }
}
