import 'dart:ui';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../domain/master_league_plan.dart';

class PlanPriceInfo {
  final double amount;
  final String currency;

  const PlanPriceInfo({
    required this.amount,
    required this.currency,
  });
}

class MasterLeaguePricingService {
  Locale _effectiveLocale(Locale? locale) {
    final base = locale ?? const Locale('en', 'US');
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return Locale(
        base.languageCode.isNotEmpty ? base.languageCode : 'en',
        forced,
      );
    }
    return base;
  }

  /// Get the price for a specific plan + duration.
  Future<PlanPriceInfo?> getPlanPrice({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required Locale? locale,
  }) async {
    final effectiveLoc = _effectiveLocale(locale);
    final remotePlan = await RemotePricingService.instance.getPlanForLocale(
      effectiveLoc,
    );

    final amount = remotePlan.getPlanPrice(
      planId: plan.id,
      durationId: duration.id,
    );

    if (amount <= 0) return null;

    return PlanPriceInfo(
      amount: amount,
      currency: remotePlan.currency,
    );
  }

  /// Get all duration prices for a plan.
  Future<Map<PlanDuration, PlanPriceInfo>> getAllDurationPrices({
    required MasterLeaguePlan plan,
    required Locale? locale,
  }) async {
    final effectiveLoc = _effectiveLocale(locale);
    final remotePlan = await RemotePricingService.instance.getPlanForLocale(
      effectiveLoc,
    );

    final out = <PlanDuration, PlanPriceInfo>{};

    for (final dur in PlanDuration.values) {
      final amount = remotePlan.getPlanPrice(
        planId: plan.id,
        durationId: dur.id,
      );

      if (amount > 0) {
        out[dur] = PlanPriceInfo(
          amount: amount,
          currency: remotePlan.currency,
        );
      }
    }

    return out;
  }

  /// Legacy method for backward compat.
  Future<PlanPriceInfo?> getMasterLeaguePriceForPlan({
    required MasterLeaguePlan plan,
    required Locale? locale,
  }) async {
    return getPlanPrice(
      plan: plan,
      duration: PlanDuration.threeMonths,
      locale: locale,
    );
  }
}
