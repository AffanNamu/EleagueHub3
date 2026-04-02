import 'package:cloud_firestore/cloud_firestore.dart';

import 'remote_pricing_service.dart';

class AppPricingAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _primaryDoc =>
      _firestore.collection('app_config').doc('pricing');

  DocumentReference<Map<String, dynamic>> get _legacyDoc =>
      _firestore.collection('app').doc('pricing');

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchDoc() async {
    final primary = await _primaryDoc.get();
    if (primary.exists) return primary;
    return _legacyDoc.get();
  }

  Future<Map<String, dynamic>> fetch() async {
    final snap = await _fetchDoc();
    if (!snap.exists) {
      return {
        'ngn': _planToMap(RemotePricingPlan.defaultsNgn()),
        'usd': _planToMap(RemotePricingPlan.defaultsUsd()),
      };
    }

    final data = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final ngn =
        (data['ngn'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final usd =
        (data['usd'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final mergedNgn = {
      ..._planToMap(RemotePricingPlan.defaultsNgn()),
      ..._normalizeKeys(ngn),
    };
    final mergedUsd = {
      ..._planToMap(RemotePricingPlan.defaultsUsd()),
      ..._normalizeKeys(usd),
    };

    return {
      'ngn': mergedNgn,
      'usd': mergedUsd,
      'updatedAtMs': data['updatedAtMs'],
      'updatedBy': data['updatedBy'],
    };
  }

  Map<String, dynamic> _normalizeKeys(Map<String, dynamic> src) {
    final out = Map<String, dynamic>.from(src);

    if (out.containsKey('createLeagueFee') && !out.containsKey('createFee')) {
      out['createFee'] = out['createLeagueFee'];
    }

    out['masterLeagueBasicFee'] ??=
        (out['masterLinkBasicFee'] ?? out['masterLinkFee'] ?? out['masterLeagueFee']);
    out['masterLeagueProFee'] ??=
        (out['masterLinkProFee'] ?? out['masterLinkFee'] ?? out['masterLeagueFee']);
    out['masterLeagueEliteFee'] ??=
        (out['masterLinkEliteFee'] ?? out['masterLinkFee'] ?? out['masterLeagueFee']);

    out['organizerVerificationFee'] ??= (out['verificationFee'] ?? 0);
    out['organizerVerificationEnabled'] ??=
        (out['verificationEnabled'] ?? true);

    out['organizerVerificationRenewalFee'] ??=
        (out['verificationRenewalFee'] ?? out['organizerVerificationFee'] ?? out['verificationFee'] ?? 0);
    out['organizerVerificationRenewalEnabled'] ??=
        (out['verificationRenewalEnabled'] ?? true);
    out['organizerVerificationDurationDays'] ??=
        (out['verificationDurationDays'] ?? 90);

    out['paymentsEnabled'] ??= true;
    out['flutterwaveEnabled'] ??= true;

    return out;
  }

  Future<void> save({
    required Map<String, dynamic> ngn,
    required Map<String, dynamic> usd,
  }) async {
    Map<String, dynamic> sanitize(Map<String, dynamic> src, bool isUsd) {
      double toDouble(dynamic v, double fallback) {
        if (v == null) return fallback;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.trim()) ?? fallback;
        return fallback;
      }

      int toInt(dynamic v, int fallback) {
        if (v == null) return fallback;
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v.trim()) ?? fallback;
        return fallback;
      }

      bool toBool(dynamic v, bool fallback) {
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

      final basicFee = toDouble(
        src['masterLeagueBasicFee'] ?? src['masterLinkBasicFee'] ?? src['masterLinkFee'],
        dft.masterLeagueBasicFee,
      );
      final proFee = toDouble(
        src['masterLeagueProFee'] ?? src['masterLinkProFee'] ?? src['masterLinkFee'],
        dft.masterLeagueProFee,
      );
      final eliteFee = toDouble(
        src['masterLeagueEliteFee'] ?? src['masterLinkEliteFee'] ?? src['masterLinkFee'],
        dft.masterLeagueEliteFee,
      );

      final verificationFee = toDouble(
        src['organizerVerificationFee'] ?? src['verificationFee'],
        dft.organizerVerificationFee,
      );
      final verificationEnabled = toBool(
        src['organizerVerificationEnabled'] ?? src['verificationEnabled'],
        dft.organizerVerificationEnabled,
      );

      final renewalFee = toDouble(
        src['organizerVerificationRenewalFee'] ?? src['verificationRenewalFee'],
        dft.organizerVerificationRenewalFee,
      );
      final renewalEnabled = toBool(
        src['organizerVerificationRenewalEnabled'] ??
            src['verificationRenewalEnabled'],
        dft.organizerVerificationRenewalEnabled,
      );
      final renewalDays = toInt(
        src['organizerVerificationDurationDays'] ??
            src['verificationDurationDays'],
        dft.organizerVerificationDurationDays,
      );

      return <String, dynamic>{
        'createFee': toDouble(src['createFee'], dft.createLeagueFee),
        'accessFee': toDouble(src['accessFee'], dft.accessFee),
        'couponUnit': toDouble(src['couponUnit'], dft.couponUnit),
        'couponThreshold': src['couponThreshold'] == null
            ? null
            : toDouble(src['couponThreshold'], dft.couponThreshold ?? 0),
        'couponDiscountPercent':
            toDouble(src['couponDiscountPercent'], dft.couponDiscountPercent),
        'viewersEnabled': toBool(src['viewersEnabled'], false),
        'premiumFee': toDouble(src['premiumFee'], dft.premiumFee),
        'premiumDurationDays':
            toInt(src['premiumDurationDays'], dft.premiumDurationDays),
        'premiumEnabled': toBool(src['premiumEnabled'], dft.premiumEnabled),

        // Plan subscription pricing
        'proPlan3moFee': toDouble(src['proPlan3moFee'], dft.proPlan3moFee),
        'proPlan6moFee': toDouble(src['proPlan6moFee'], dft.proPlan6moFee),
        'proPlanYearlyFee': toDouble(src['proPlanYearlyFee'], dft.proPlanYearlyFee),
        'elitePlan3moFee': toDouble(src['elitePlan3moFee'], dft.elitePlan3moFee),
        'elitePlan6moFee': toDouble(src['elitePlan6moFee'], dft.elitePlan6moFee),
        'elitePlanYearlyFee': toDouble(src['elitePlanYearlyFee'], dft.elitePlanYearlyFee),

        // Legacy single-price fields
        'masterLeagueBasicFee': basicFee,
        'masterLeagueProFee': proFee,
        'masterLeagueEliteFee': eliteFee,
        'organizerVerificationFee': verificationFee,
        'organizerVerificationEnabled': verificationEnabled,
        'organizerVerificationRenewalFee': renewalFee,
        'organizerVerificationRenewalEnabled': renewalEnabled,
        'organizerVerificationDurationDays': renewalDays,

        'masterLinkBasicFee': basicFee,
        'masterLinkProFee': proFee,
        'masterLinkEliteFee': eliteFee,
        'masterLinkFee': proFee,
        'masterLeagueFee': proFee,
        'verificationFee': verificationFee,
        'verificationEnabled': verificationEnabled,
        'verificationRenewalFee': renewalFee,
        'verificationRenewalEnabled': renewalEnabled,
        'verificationDurationDays': renewalDays,

        'paymentsEnabled': toBool(src['paymentsEnabled'], true),
        'flutterwaveEnabled': toBool(src['flutterwaveEnabled'], true),
      };
    }

    final ngnSan = sanitize(ngn, false);
    final usdSan = sanitize(usd, true);

    final now = DateTime.now().millisecondsSinceEpoch;

    final payload = {
      'ngn': ngnSan,
      'usd': usdSan,
      'updatedAtMs': now,
    };

    await _primaryDoc.set(payload, SetOptions(merge: true));
    await _legacyDoc.set(payload, SetOptions(merge: true));
  }

  Map<String, dynamic> _planToMap(RemotePricingPlan p) => {
        'createFee': p.createLeagueFee,
        'accessFee': p.accessFee,
        'couponUnit': p.couponUnit,
        'couponThreshold': p.couponThreshold,
        'couponDiscountPercent': p.couponDiscountPercent,
        'viewersEnabled': p.viewersEnabled,
        'premiumFee': p.premiumFee,
        'premiumDurationDays': p.premiumDurationDays,
        'premiumEnabled': p.premiumEnabled,

        'proPlan3moFee': p.proPlan3moFee,
        'proPlan6moFee': p.proPlan6moFee,
        'proPlanYearlyFee': p.proPlanYearlyFee,
        'elitePlan3moFee': p.elitePlan3moFee,
        'elitePlan6moFee': p.elitePlan6moFee,
        'elitePlanYearlyFee': p.elitePlanYearlyFee,

        'masterLeagueBasicFee': p.masterLeagueBasicFee,
        'masterLeagueProFee': p.masterLeagueProFee,
        'masterLeagueEliteFee': p.masterLeagueEliteFee,
        'organizerVerificationFee': p.organizerVerificationFee,
        'organizerVerificationEnabled': p.organizerVerificationEnabled,
        'organizerVerificationRenewalFee': p.organizerVerificationRenewalFee,
        'organizerVerificationRenewalEnabled':
            p.organizerVerificationRenewalEnabled,
        'organizerVerificationDurationDays':
            p.organizerVerificationDurationDays,
        'masterLinkBasicFee': p.masterLeagueBasicFee,
        'masterLinkProFee': p.masterLeagueProFee,
        'masterLinkEliteFee': p.masterLeagueEliteFee,
        'masterLinkFee': p.masterLeagueProFee,
        'masterLeagueFee': p.masterLeagueProFee,
        'verificationFee': p.organizerVerificationFee,
        'verificationEnabled': p.organizerVerificationEnabled,
        'verificationRenewalFee': p.organizerVerificationRenewalFee,
        'verificationRenewalEnabled': p.organizerVerificationRenewalEnabled,
        'verificationDurationDays': p.organizerVerificationDurationDays,
        'paymentsEnabled': p.paymentsEnabled,
        'flutterwaveEnabled': p.flutterwaveEnabled,
      };
}
