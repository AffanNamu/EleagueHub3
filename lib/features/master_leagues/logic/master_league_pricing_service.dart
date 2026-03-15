import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/country/country_resolver_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../domain/master_league_plan.dart';

class MasterLeaguePrice {
  final String currency;
  final num amount;

  const MasterLeaguePrice({
    required this.currency,
    required this.amount,
  });

  String get display {
    final a = amount;
    final s = (a is int) ? '$a' : a.toString();
    return '$currency $s';
  }
}

class MasterLeaguePricingService {
  MasterLeaguePricingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<DocumentSnapshot<Map<String, dynamic>>> _getPricingDoc() async {
    final primary = await _firestore
        .collection('app_config')
        .doc('pricing')
        .get(const GetOptions(source: Source.server));
    if (primary.exists) return primary;

    return _firestore
        .collection('app')
        .doc('pricing')
        .get(const GetOptions(source: Source.server));
  }

  static String _planFeeKey(MasterLeaguePlan plan) {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return 'masterLeagueBasicFee';
      case MasterLeaguePlan.pro:
        return 'masterLeagueProFee';
      case MasterLeaguePlan.elite:
        return 'masterLeagueEliteFee';
    }
  }

  static String _legacyPlanFeeKey(MasterLeaguePlan plan) {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return 'masterLinkBasicFee';
      case MasterLeaguePlan.pro:
        return 'masterLinkProFee';
      case MasterLeaguePlan.elite:
        return 'masterLinkEliteFee';
    }
  }

  num? _extractFee(Map<String, dynamic> currencyMap, MasterLeaguePlan? plan) {
    if (plan != null) {
      final v = currencyMap[_planFeeKey(plan)];
      if (v is num) return v;

      final lv = currencyMap[_legacyPlanFeeKey(plan)];
      if (lv is num) return lv;
    }

    final v1 = currencyMap['masterLeagueFee'];
    if (v1 is num) return v1;

    final v2 = currencyMap['masterLinkFee'];
    if (v2 is num) return v2;

    return null;
  }

  MasterLeaguePrice? _priceFromPricingDoc(
    Map<String, dynamic> data, {
    required bool preferNgn,
    MasterLeaguePlan? plan,
  }) {
    Map<String, dynamic> usd = const <String, dynamic>{};
    Map<String, dynamic> ngn = const <String, dynamic>{};

    final rawUsd = data['usd'];
    if (rawUsd is Map) usd = rawUsd.cast<String, dynamic>();

    final rawNgn = data['ngn'];
    if (rawNgn is Map) ngn = rawNgn.cast<String, dynamic>();

    final feeUsd = _extractFee(usd, plan);
    final feeNgn = _extractFee(ngn, plan);

    if (preferNgn && feeNgn != null) {
      return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);
    }
    if (!preferNgn && feeUsd != null) {
      return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    }

    if (feeUsd != null) {
      return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    }
    if (feeNgn != null) {
      return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);
    }

    return null;
  }

  Future<bool> _preferNgn(Locale? locale) async {
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    final cc = forced.isNotEmpty
        ? forced
        : await CountryResolverService.instance.resolveCountryCode(
            locale: locale,
          );
    return cc == 'NG';
  }

  Future<MasterLeaguePrice?> getMasterLeaguePriceForLocale(Locale? locale) async {
    final preferNgn = await _preferNgn(locale);

    final snap = await _getPricingDoc().timeout(const Duration(seconds: 12));
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(
      data,
      preferNgn: preferNgn,
      plan: MasterLeaguePlan.pro,
    );
  }

  Future<MasterLeaguePrice?> getMasterLeaguePriceForPlan({
    required MasterLeaguePlan plan,
    Locale? locale,
  }) async {
    final preferNgn = await _preferNgn(locale);

    final snap = await _getPricingDoc().timeout(const Duration(seconds: 12));
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(data, preferNgn: preferNgn, plan: plan);
  }

  Stream<MasterLeaguePrice?> watchMasterLeaguePriceForLocale(Locale? locale) {
    final preferNgn =
        (locale?.countryCode ?? '').trim().toUpperCase() == 'NG';

    return _firestore
        .collection('app_config')
        .doc('pricing')
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _priceFromPricingDoc(
        data,
        preferNgn: preferNgn,
        plan: MasterLeaguePlan.pro,
      );
    });
  }

  Future<RemotePricingPlan> getUnifiedPlanForLocale(Locale? locale) {
    return RemotePricingService.instance.getPlanForLocale(locale);
  }
}
