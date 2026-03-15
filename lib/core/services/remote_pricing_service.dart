import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/flutterwave_config.dart';
import 'country/country_resolver_service.dart';

class RemotePricingPlan {
  final String currency;
  final double createLeagueFee;
  final double accessFee;
  final double couponUnit;
  final double? couponThreshold;
  final double couponDiscountPercent;
  final bool viewersEnabled;

  final double premiumFee;
  final int premiumDurationDays;
  final bool premiumEnabled;

  final double masterLeagueBasicFee;
  final double masterLeagueProFee;
  final double masterLeagueEliteFee;

  final bool paymentsEnabled;
  final bool flutterwaveEnabled;

  const RemotePricingPlan({
    required this.currency,
    required this.createLeagueFee,
    required this.accessFee,
    required this.couponUnit,
    required this.couponThreshold,
    required this.couponDiscountPercent,
    required this.viewersEnabled,
    required this.premiumFee,
    required this.premiumDurationDays,
    required this.premiumEnabled,
    required this.masterLeagueBasicFee,
    required this.masterLeagueProFee,
    required this.masterLeagueEliteFee,
    required this.paymentsEnabled,
    required this.flutterwaveEnabled,
  });

  RemotePricingPlan copyWith({
    String? currency,
    double? createLeagueFee,
    double? accessFee,
    double? couponUnit,
    double? couponThreshold,
    double? couponDiscountPercent,
    bool? viewersEnabled,
    double? premiumFee,
    int? premiumDurationDays,
    bool? premiumEnabled,
    double? masterLeagueBasicFee,
    double? masterLeagueProFee,
    double? masterLeagueEliteFee,
    bool? paymentsEnabled,
    bool? flutterwaveEnabled,
  }) {
    return RemotePricingPlan(
      currency: currency ?? this.currency,
      createLeagueFee: createLeagueFee ?? this.createLeagueFee,
      accessFee: accessFee ?? this.accessFee,
      couponUnit: couponUnit ?? this.couponUnit,
      couponThreshold: couponThreshold ?? this.couponThreshold,
      couponDiscountPercent: couponDiscountPercent ?? this.couponDiscountPercent,
      viewersEnabled: viewersEnabled ?? this.viewersEnabled,
      premiumFee: premiumFee ?? this.premiumFee,
      premiumDurationDays: premiumDurationDays ?? this.premiumDurationDays,
      premiumEnabled: premiumEnabled ?? this.premiumEnabled,
      masterLeagueBasicFee: masterLeagueBasicFee ?? this.masterLeagueBasicFee,
      masterLeagueProFee: masterLeagueProFee ?? this.masterLeagueProFee,
      masterLeagueEliteFee: masterLeagueEliteFee ?? this.masterLeagueEliteFee,
      paymentsEnabled: paymentsEnabled ?? this.paymentsEnabled,
      flutterwaveEnabled: flutterwaveEnabled ?? this.flutterwaveEnabled,
    );
  }

  factory RemotePricingPlan.defaultsUsd() => const RemotePricingPlan(
        currency: 'USD',
        createLeagueFee: 5.0,
        accessFee: 1.5,
        couponUnit: 1.5,
        couponThreshold: 20.0,
        couponDiscountPercent: 30.0,
        viewersEnabled: false,
        premiumFee: 9.99,
        premiumDurationDays: 30,
        premiumEnabled: true,
        masterLeagueBasicFee: 5.0,
        masterLeagueProFee: 10.0,
        masterLeagueEliteFee: 20.0,
        paymentsEnabled: true,
        flutterwaveEnabled: true,
      );

  factory RemotePricingPlan.defaultsNgn() => const RemotePricingPlan(
        currency: 'NGN',
        createLeagueFee: 4000.0,
        accessFee: 1000.0,
        couponUnit: 1000.0,
        couponThreshold: null,
        couponDiscountPercent: 30.0,
        viewersEnabled: false,
        premiumFee: 5000.0,
        premiumDurationDays: 30,
        premiumEnabled: true,
        masterLeagueBasicFee: 1500.0,
        masterLeagueProFee: 3000.0,
        masterLeagueEliteFee: 5000.0,
        paymentsEnabled: true,
        flutterwaveEnabled: true,
      );

  static double _numToDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static bool _boolFromAny(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return fallback;
  }

  static int _numToInt(dynamic v, {int fallback = 30}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static RemotePricingPlan fromMap({
    required String currency,
    required Map<String, dynamic> map,
    required RemotePricingPlan defaults,
  }) {
    final createFee = map.containsKey('createFee')
        ? map['createFee']
        : map['createLeagueFee'];

    final paymentsEnabled =
        map.containsKey('paymentsEnabled') ? map['paymentsEnabled'] : true;
    final flutterwaveEnabled =
        map.containsKey('flutterwaveEnabled') ? map['flutterwaveEnabled'] : true;

    final mlBasic = map['masterLeagueBasicFee'] ??
        map['masterLinkBasicFee'] ??
        map['masterLinkFee'] ??
        map['masterLeagueFee'];

    final mlPro = map['masterLeagueProFee'] ??
        map['masterLinkProFee'] ??
        map['masterLinkFee'] ??
        map['masterLeagueFee'];

    final mlElite = map['masterLeagueEliteFee'] ??
        map['masterLinkEliteFee'] ??
        map['masterLinkFee'] ??
        map['masterLeagueFee'];

    return RemotePricingPlan(
      currency: currency,
      createLeagueFee:
          _numToDouble(createFee, fallback: defaults.createLeagueFee),
      accessFee: _numToDouble(map['accessFee'], fallback: defaults.accessFee),
      couponUnit: _numToDouble(map['couponUnit'], fallback: defaults.couponUnit),
      couponThreshold: map.containsKey('couponThreshold')
          ? (_numToDouble(
                      map['couponThreshold'],
                      fallback: defaults.couponThreshold ?? 0) ==
                  0
              ? null
              : _numToDouble(
                  map['couponThreshold'],
                  fallback: defaults.couponThreshold ?? 0))
          : defaults.couponThreshold,
      couponDiscountPercent: _numToDouble(
        map['couponDiscountPercent'],
        fallback: defaults.couponDiscountPercent,
      ),
      viewersEnabled:
          _boolFromAny(map['viewersEnabled'], fallback: defaults.viewersEnabled),
      premiumFee: _numToDouble(map['premiumFee'], fallback: defaults.premiumFee),
      premiumDurationDays: _numToInt(
        map['premiumDurationDays'],
        fallback: defaults.premiumDurationDays,
      ),
      premiumEnabled:
          _boolFromAny(map['premiumEnabled'], fallback: defaults.premiumEnabled),
      masterLeagueBasicFee:
          _numToDouble(mlBasic, fallback: defaults.masterLeagueBasicFee),
      masterLeagueProFee:
          _numToDouble(mlPro, fallback: defaults.masterLeagueProFee),
      masterLeagueEliteFee:
          _numToDouble(mlElite, fallback: defaults.masterLeagueEliteFee),
      paymentsEnabled:
          _boolFromAny(paymentsEnabled, fallback: defaults.paymentsEnabled),
      flutterwaveEnabled:
          _boolFromAny(flutterwaveEnabled, fallback: defaults.flutterwaveEnabled),
    );
  }
}

class OrganizerCouponPricing {
  final double organizerUnit;
  final int qty;
  final double rawSubtotal;
  final double discountedSubtotal;
  final bool bulkDiscountApplied;

  const OrganizerCouponPricing({
    required this.organizerUnit,
    required this.qty,
    required this.rawSubtotal,
    required this.discountedSubtotal,
    required this.bulkDiscountApplied,
  });
}

class _RemotePricingCache {
  final DateTime fetchedAt;
  final RemotePricingPlan ngn;
  final RemotePricingPlan usd;

  const _RemotePricingCache({
    required this.fetchedAt,
    required this.ngn,
    required this.usd,
  });

  bool get isFresh => DateTime.now().difference(fetchedAt).inMinutes < 10;
}

class RemotePricingService {
  RemotePricingService._();
  static final RemotePricingService instance = RemotePricingService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  _RemotePricingCache? _cache;

  Future<DocumentSnapshot<Map<String, dynamic>>> _getPricingDoc() async {
    final primary = await _firestore.collection('app_config').doc('pricing').get();
    if (primary.exists) return primary;
    return _firestore.collection('app').doc('pricing').get();
  }

  Future<_RemotePricingCache> _fetch() async {
    try {
      final doc = await _getPricingDoc();
      if (!doc.exists) {
        return _RemotePricingCache(
          fetchedAt: DateTime.now(),
          ngn: RemotePricingPlan.defaultsNgn(),
          usd: RemotePricingPlan.defaultsUsd(),
        );
      }

      final raw = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final ngnMap =
          (raw['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final usdMap =
          (raw['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final ngn = RemotePricingPlan.fromMap(
        currency: 'NGN',
        map: ngnMap,
        defaults: RemotePricingPlan.defaultsNgn(),
      );

      final usd = RemotePricingPlan.fromMap(
        currency: 'USD',
        map: usdMap,
        defaults: RemotePricingPlan.defaultsUsd(),
      );

      return _RemotePricingCache(
        fetchedAt: DateTime.now(),
        ngn: ngn,
        usd: usd,
      );
    } catch (_) {
      return _RemotePricingCache(
        fetchedAt: DateTime.now(),
        ngn: RemotePricingPlan.defaultsNgn(),
        usd: RemotePricingPlan.defaultsUsd(),
      );
    }
  }

  bool _isNigeriaCountryCode(String? countryCode) {
    final c = (countryCode ?? '').trim().toUpperCase();
    return c == 'NG';
  }

  Future<RemotePricingPlan> getPlanForLocale(Locale? locale) async {
    if (_cache == null || !_cache!.isFresh) {
      _cache = await _fetch();
    }

    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return _isNigeriaCountryCode(forced) ? _cache!.ngn : _cache!.usd;
    }

    final cc =
        await CountryResolverService.instance.resolveCountryCode(locale: locale);
    if (_isNigeriaCountryCode(cc)) return _cache!.ngn;
    return _cache!.usd;
  }

  Stream<RemotePricingPlan> watchPlanForLocale(Locale? locale) async* {
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    final useNgn = forced.isNotEmpty
        ? _isNigeriaCountryCode(forced)
        : (locale?.countryCode ?? '').trim().toUpperCase() == 'NG';

    yield* _firestore
        .collection('app_config')
        .doc('pricing')
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final raw = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final ngnMap =
          (raw['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final usdMap =
          (raw['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final ngn = RemotePricingPlan.fromMap(
        currency: 'NGN',
        map: ngnMap,
        defaults: RemotePricingPlan.defaultsNgn(),
      );
      final usd = RemotePricingPlan.fromMap(
        currency: 'USD',
        map: usdMap,
        defaults: RemotePricingPlan.defaultsUsd(),
      );
      return useNgn ? ngn : usd;
    });
  }

  double _roundMoney(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return v.roundToDouble();
    return _round2(v);
  }

  double couponSubtotalWithThresholdDiscount({
    required RemotePricingPlan plan,
    required int couponCount,
  }) {
    final qty = couponCount < 0 ? 0 : couponCount;
    if (qty == 0) return 0.0;

    final subtotal = plan.couponUnit * qty;
    final threshold = plan.couponThreshold;
    if (threshold == null) return _roundMoney(plan.currency, subtotal);

    if (subtotal >= threshold) {
      final pct =
          (plan.couponDiscountPercent <= 0) ? 0 : plan.couponDiscountPercent;
      final discounted = subtotal * ((100.0 - pct) / 100.0);
      return _roundMoney(plan.currency, discounted);
    }

    return _roundMoney(plan.currency, subtotal);
  }

  OrganizerCouponPricing computeOrganizerCouponPricing({
    required RemotePricingPlan plan,
    required int couponCount,
    required int discountPercent,
  }) {
    final qty = couponCount < 0 ? 0 : couponCount;
    final disc = discountPercent.clamp(0, 100);

    if (qty == 0) {
      return const OrganizerCouponPricing(
        organizerUnit: 0.0,
        qty: 0,
        rawSubtotal: 0.0,
        discountedSubtotal: 0.0,
        bulkDiscountApplied: false,
      );
    }

    final organizerUnit = plan.couponUnit * (disc / 100.0);
    final rawSubtotalUnrounded = organizerUnit * qty;

    final threshold = plan.couponThreshold;
    final thresholdConfigured = threshold != null && threshold > 0;
    final pct = (plan.couponDiscountPercent <= 0) ? 0 : plan.couponDiscountPercent;

    bool bulkApplied = false;
    double discountedSubtotalUnrounded = rawSubtotalUnrounded;

    if (thresholdConfigured && rawSubtotalUnrounded >= threshold!) {
      bulkApplied = true;
      discountedSubtotalUnrounded = rawSubtotalUnrounded * ((100.0 - pct) / 100.0);
    }

    return OrganizerCouponPricing(
      organizerUnit: organizerUnit,
      qty: qty,
      rawSubtotal: _roundMoney(plan.currency, rawSubtotalUnrounded),
      discountedSubtotal:
          _roundMoney(plan.currency, discountedSubtotalUnrounded),
      bulkDiscountApplied: bulkApplied,
    );
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
