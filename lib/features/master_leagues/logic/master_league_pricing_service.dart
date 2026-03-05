import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

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
/// Firestore:
/// app/pricing
///  - usd.masterLeagueFee
///  - ngn.masterLeagueFee
class MasterLeaguePricingService {
  MasterLeaguePricingService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  MasterLeaguePrice? _priceFromPricingDoc(Map<String, dynamic> data, Locale? locale) {
    Map<String, dynamic> usd = const <String, dynamic>{};
    Map<String, dynamic> ngn = const <String, dynamic>{};

    final rawUsd = data['usd'];
    if (rawUsd is Map) usd = rawUsd.cast<String, dynamic>();

    final rawNgn = data['ngn'];
    if (rawNgn is Map) ngn = rawNgn.cast<String, dynamic>();

    final country = (locale?.countryCode ?? '').trim().toUpperCase();
    final preferNgn = country == 'NG';

    num? feeUsd = usd['masterLeagueFee'] is num ? usd['masterLeagueFee'] as num : null;
    num? feeNgn = ngn['masterLeagueFee'] is num ? ngn['masterLeagueFee'] as num : null;

    // Backward compatible fallback (if pricing not set yet).
    feeUsd ??= usd['createLeagueFee'] is num ? usd['createLeagueFee'] as num : null;
    feeNgn ??= ngn['createLeagueFee'] is num ? ngn['createLeagueFee'] as num : null;

    if (preferNgn && feeNgn != null) {
      return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);
    }
    if (!preferNgn && feeUsd != null) {
      return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    }

    // Last-resort fallback
    if (feeUsd != null) return MasterLeaguePrice(currency: 'USD', amount: feeUsd);
    if (feeNgn != null) return MasterLeaguePrice(currency: 'NGN', amount: feeNgn);

    return null;
  }

  /// One-time server fetch (used by dialogs).
  Future<MasterLeaguePrice?> getMasterLeaguePriceForLocale(Locale? locale) async {
    final snap = await _firestore
        .collection('app')
        .doc('pricing')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return _priceFromPricingDoc(data, locale);
  }

  /// Live watch (used by Profile UI so pricing updates show immediately).
  Stream<MasterLeaguePrice?> watchMasterLeaguePriceForLocale(Locale? locale) {
    return _firestore.collection('app').doc('pricing').snapshots(includeMetadataChanges: true).map((snap) {
      final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      return _priceFromPricingDoc(data, locale);
    });
  }
}
