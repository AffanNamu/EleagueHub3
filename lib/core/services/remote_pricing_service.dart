import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/flutterwave_config.dart';

class RemotePricingPlan {
  final String currency; // 'NGN' or 'USD'
  final double createLeagueFee; // mandatory league creation fee
  final double accessFee; // paywall fee when no coupons apply (kept for guard)
  final double couponUnit; // price per coupon unit
  final double? couponThreshold; // subtotal threshold to apply discount
  final double couponDiscountPercent; // discount percent when threshold is met
  final bool viewersEnabled; // legacy switch

  const RemotePricingPlan({
    required this.currency,
    required this.createLeagueFee,
    required this.accessFee,
    required this.couponUnit,
    required this.couponThreshold,
    required this.couponDiscountPercent,
    required this.viewersEnabled,
  });

  RemotePricingPlan copyWith({
    String? currency,
    double? createLeagueFee,
    double? accessFee,
    double? couponUnit,
    double? couponThreshold,
    double? couponDiscountPercent,
    bool? viewersEnabled,
  }) {
    return RemotePricingPlan(
      currency: currency ?? this.currency,
      createLeagueFee: createLeagueFee ?? this.createLeagueFee,
      accessFee: accessFee ?? this.accessFee,
      couponUnit: couponUnit ?? this.couponUnit,
      couponThreshold: couponThreshold ?? this.couponThreshold,
      couponDiscountPercent: couponDiscountPercent ?? this.couponDiscountPercent,
      viewersEnabled: viewersEnabled ?? this.viewersEnabled,
    );
  }

  // Defaults when /app/pricing missing or unreadable.
  factory RemotePricingPlan.defaultsUsd() => const RemotePricingPlan(
        currency: 'USD',
        createLeagueFee: 5.0,
        accessFee: 1.5,
        couponUnit: 1.5,
        couponThreshold: 20.0,
        couponDiscountPercent: 30.0,
        viewersEnabled: false,
      );

  factory RemotePricingPlan.defaultsNgn() => const RemotePricingPlan(
        currency: 'NGN',
        createLeagueFee: 4000.0,
        accessFee: 1000.0,
        couponUnit: 1000.0,
        couponThreshold: null,
        couponDiscountPercent: 30.0,
        viewersEnabled: false,
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

  static RemotePricingPlan fromMap({
    required String currency,
    required Map<String, dynamic> map,
    required RemotePricingPlan defaults,
  }) {
    return RemotePricingPlan(
      currency: currency,
      createLeagueFee: _numToDouble(map['createFee'], fallback: defaults.createLeagueFee),
      accessFee: _numToDouble(map['accessFee'], fallback: defaults.accessFee),
      couponUnit: _numToDouble(map['couponUnit'], fallback: defaults.couponUnit),
      couponThreshold: map.containsKey('couponThreshold')
          ? (_numToDouble(map['couponThreshold'], fallback: defaults.couponThreshold ?? 0) == 0
              ? null
              : _numToDouble(map['couponThreshold'], fallback: defaults.couponThreshold ?? 0))
          : defaults.couponThreshold,
      couponDiscountPercent: _numToDouble(map['couponDiscountPercent'], fallback: defaults.couponDiscountPercent),
      viewersEnabled: _boolFromAny(map['viewersEnabled'], fallback: defaults.viewersEnabled),
    );
  }
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

  Future<_RemotePricingCache> _fetch() async {
    try {
      final doc = await _firestore.collection('app').doc('pricing').get();
      if (!doc.exists) {
        return _RemotePricingCache(
          fetchedAt: DateTime.now(),
          ngn: RemotePricingPlan.defaultsNgn(),
          usd: RemotePricingPlan.defaultsUsd(),
        );
      }

      final raw = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
      final ngnMap = (raw['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final usdMap = (raw['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

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
      // Fail-safe to defaults if Firestore unavailable or rules deny.
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

  // Resolve the plan (NGN vs USD) using forced country first, then locale.
  Future<RemotePricingPlan> getPlanForLocale(Locale? locale) async {
    if (_cache == null || !_cache!.isFresh) {
      _cache = await _fetch();
    }

    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return _isNigeriaCountryCode(forced) ? _cache!.ngn : _cache!.usd;
    }

    final cc = (locale?.countryCode ?? '').trim().toUpperCase();
    if (_isNigeriaCountryCode(cc)) {
      return _cache!.ngn;
    }
    return _cache!.usd;
  }

  double _roundMoney(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return v.roundToDouble();
    return _round2(v);
  }

  // Compute coupon subtotal (applies discount only when threshold is set and reached).
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
      final pct = (plan.couponDiscountPercent <= 0) ? 0 : plan.couponDiscountPercent;
      final discounted = subtotal * ((100.0 - pct) / 100.0);
      return _roundMoney(plan.currency, discounted);
    }

    return _roundMoney(plan.currency, subtotal);
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
