import 'package:cloud_firestore/cloud_firestore.dart';

import 'remote_pricing_service.dart';

class AppPricingAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('app').doc('pricing');

  Future<Map<String, dynamic>> fetch() async {
    final snap = await _doc.get();
    if (!snap.exists) {
      // Return safe defaults if doc missing
      return {
        'ngn': _ngnFromPlan(RemotePricingPlan.defaultsNgn()),
        'usd': _usdFromPlan(RemotePricingPlan.defaultsUsd()),
      };
    }
    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final ngn = (data['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final usd = (data['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    // Fill missing with defaults
    final mergedNgn = {
      ..._ngnFromPlan(RemotePricingPlan.defaultsNgn()),
      ...ngn,
    };
    final mergedUsd = {
      ..._usdFromPlan(RemotePricingPlan.defaultsUsd()),
      ...usd,
    };

    return {
      'ngn': mergedNgn,
      'usd': mergedUsd,
    };
  }

  Future<void> save({
    required Map<String, dynamic> ngn,
    required Map<String, dynamic> usd,
  }) async {
    // Basic sanitize: ensure required fields exist and are numbers/bools.
    Map<String, dynamic> _sanitize(Map<String, dynamic> src, bool isUsd) {
      double _toDouble(dynamic v, double fallback) {
        if (v == null) return fallback;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.trim()) ?? fallback;
        return fallback;
      }
      bool _toBool(dynamic v, bool fallback) {
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

      final dft = isUsd
          ? RemotePricingPlan.defaultsUsd()
          : RemotePricingPlan.defaultsNgn();

      return <String, dynamic>{
        'createFee': _toDouble(src['createFee'], dft.createLeagueFee),
        'accessFee': _toDouble(src['accessFee'], dft.accessFee),
        'couponUnit': _toDouble(src['couponUnit'], dft.couponUnit),
        // threshold can be null
        'couponThreshold': src['couponThreshold'] == null
            ? null
            : _toDouble(src['couponThreshold'], dft.couponThreshold ?? 0),
        'couponDiscountPercent': _toDouble(src['couponDiscountPercent'], dft.couponDiscountPercent),
        'viewersEnabled': _toBool(src['viewersEnabled'], false),
      };
    }

    final ngnSan = _sanitize(ngn, false);
    final usdSan = _sanitize(usd, true);

    await _doc.set({
      'ngn': ngnSan,
      'usd': usdSan,
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _ngnFromPlan(RemotePricingPlan p) => {
        'createFee': p.createLeagueFee,
        'accessFee': p.accessFee,
        'couponUnit': p.couponUnit,
        'couponThreshold': p.couponThreshold,
        'couponDiscountPercent': p.couponDiscountPercent,
        'viewersEnabled': p.viewersEnabled,
      };

  Map<String, dynamic> _usdFromPlan(RemotePricingPlan p) => {
        'createFee': p.createLeagueFee,
        'accessFee': p.accessFee,
        'couponUnit': p.couponUnit,
        'couponThreshold': p.couponThreshold,
        'couponDiscountPercent': p.couponDiscountPercent,
        'viewersEnabled': p.viewersEnabled,
      };
}
