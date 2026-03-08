import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/country/country_resolver_service.dart';
import '../domain/master_league_plan.dart';

class MasterLeaguePrice {
  final String currency; // 'USD' or 'NGN'
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

/// Reads pricing for the Master League premium unlock from Firestore.
///
/// NEW (source of truth):
///   app_config/pricing
///
/// FALLBACK (legacy):
///   app/pricing
///
/// Plan-specific keys (preferred):
/// - usd.masterLinkBasicFee / ngn.masterLinkBasicFee
/// - usd.masterLinkProFee   / ngn.masterLinkProFee
/// - usd.masterLinkEliteFee / ngn.masterLinkEliteFee
///
/// Fallback keys (legacy):
/// - usd.masterLinkFee / ngn.masterLinkFee
/// - usd.masterLeagueFee / ngn.masterLeagueFee
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

  /// Returns the Firestore key for a plan-specific fee.
  /// e.g. basic → 'masterLinkBasicFee', pro → 'masterLinkProFee'
  static String _planFeeKey(MasterLeaguePlan plan) {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return 'masterLinkBasicFee';
      case MasterLeaguePlan.pro:
        return 'masterLinkProFee';
      case MasterLeaguePlan.elite:
        return 'masterLinkEliteFee';
    }
  }

  /// Extracts a num fee from a currency map, trying plan-specific key first,
  /// then falling back to masterLinkFee → masterLeagueFee.
  num? _extractFee(Map<String, dynamic> currencyMap, MasterLeaguePlan? plan) {
    // 1. Plan-specific key
    if (plan != null) {
      final planKey = _planFeeKey(plan);
      final v = currencyMap[planKey];
      if (v is num) return v;
    }

    // 2. Generic masterLinkFee
    final v1 = currencyMap['masterLinkFee'];
    if (v1 is num) return v1;

    // 3. Legacy masterLeagueFee
    final v2 = currencyMap['masterLeagueFee'];
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
        : await CountryResolverService.instance
            .resolveCountryCode(locale: locale);
    return cc == 'NG';
  }

  /// One-time server fetch — returns price for the generic masterLinkFee
  /// (used when no plan is specified, backward compatible).
  Future<MasterLeaguePrice?> getMasterLeaguePriceForLocale(
      Locale? locale) async {
    final preferNgn = await _preferNgn(locale);

    final snap = await _getPricingDoc().timeout(const Duration(seconds: 12));
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(data, preferNgn: preferNgn);
  }

  /// One-time server fetch — returns price for a specific plan tier.
  ///
  /// Reads from admin pricing doc:
  ///   usd.masterLinkBasicFee / usd.masterLinkProFee / usd.masterLinkEliteFee
  ///   ngn.masterLinkBasicFee / ngn.masterLinkProFee / ngn.masterLinkEliteFee
  ///
  /// Falls back to masterLinkFee → masterLeagueFee if plan key not set.
  Future<MasterLeaguePrice?> getMasterLeaguePriceForPlan({
    required MasterLeaguePlan plan,
    Locale? locale,
  }) async {
    final preferNgn = await _preferNgn(locale);

    final snap = await _getPricingDoc().timeout(const Duration(seconds: 12));
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(data, preferNgn: preferNgn, plan: plan);
  }

  /// Live watch (UI convenience). Uses locale only (no IP lookup in streams).
  Stream<MasterLeaguePrice?> watchMasterLeaguePriceForLocale(Locale? locale) {
    final preferNgn =
        (locale?.countryCode ?? '').trim().toUpperCase() == 'NG';

    return _firestore
        .collection('app_config')
        .doc('pricing')
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final data =
          (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _priceFromPricingDoc(data, preferNgn: preferNgn);
    });
  }
}
