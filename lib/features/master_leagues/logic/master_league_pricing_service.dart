import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/country/country_resolver_service.dart';

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
/// Keys supported:
/// - usd.masterLinkFee (preferred)
/// - ngn.masterLinkFee (preferred)
/// - usd.masterLeagueFee (legacy)
/// - ngn.masterLeagueFee (legacy)
class MasterLeaguePricingService {
  MasterLeaguePricingService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<DocumentSnapshot<Map<String, dynamic>>> _getPricingDoc() async {
    final primary = await _firestore.collection('app_config').doc('pricing').get(const GetOptions(source: Source.server));
    if (primary.exists) return primary;

    return _firestore.collection('app').doc('pricing').get(const GetOptions(source: Source.server));
  }

  MasterLeaguePrice? _priceFromPricingDoc(Map<String, dynamic> data, {required bool preferNgn}) {
    Map<String, dynamic> usd = const <String, dynamic>{};
    Map<String, dynamic> ngn = const <String, dynamic>{};

    final rawUsd = data['usd'];
    if (rawUsd is Map) usd = rawUsd.cast<String, dynamic>();

    final rawNgn = data['ngn'];
    if (rawNgn is Map) ngn = rawNgn.cast<String, dynamic>();

    num? feeUsd = usd['masterLinkFee'] is num ? usd['masterLinkFee'] as num : null;
    num? feeNgn = ngn['masterLinkFee'] is num ? ngn['masterLinkFee'] as num : null;

    // Legacy alias
    feeUsd ??= usd['masterLeagueFee'] is num ? usd['masterLeagueFee'] as num : null;
    feeNgn ??= ngn['masterLeagueFee'] is num ? ngn['masterLeagueFee'] as num : null;

    if (preferNgn && feeNgn != null) {
      return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);
    }
    if (!preferNgn && feeUsd != null) {
      return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    }

    if (feeUsd != null) return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    if (feeNgn != null) return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);

    return null;
  }

  /// One-time server fetch (used by payment flow).
  Future<MasterLeaguePrice?> getMasterLeaguePriceForLocale(Locale? locale) async {
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    final cc = forced.isNotEmpty ? forced : await CountryResolverService.instance.resolveCountryCode(locale: locale);
    final preferNgn = cc == 'NG';

    final snap = await _getPricingDoc().timeout(const Duration(seconds: 12));
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(data, preferNgn: preferNgn);
  }

  /// Live watch (UI convenience). Uses locale only (no IP lookup in streams).
  Stream<MasterLeaguePrice?> watchMasterLeaguePriceForLocale(Locale? locale) {
    final preferNgn = (locale?.countryCode ?? '').trim().toUpperCase() == 'NG';

    // Watch new doc; if missing, UI just won’t show price (admin should migrate).
    return _firestore.collection('app_config').doc('pricing').snapshots(includeMetadataChanges: true).map((snap) {
      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _priceFromPricingDoc(data, preferNgn: preferNgn);
    });
  }
}
