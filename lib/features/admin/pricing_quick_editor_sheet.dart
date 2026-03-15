import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/errors/user_friendly_error.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/widgets/glass.dart';

const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

Future<bool> _isPricingAdminServer(String uid) async {
  final u = uid.trim();
  if (u.isEmpty) return false;
  if (u == _superAdminUid) return true;

  final snap = await FirebaseFirestore.instance
      .collection('app')
      .doc('admins')
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 10));

  if (!snap.exists) return false;

  final data = snap.data() ?? <String, dynamic>{};
  final list = data['pricingAdmins'];
  if (list is! List) return false;

  return list.map((e) => (e ?? '').toString().trim()).contains(u);
}

num? _parseNum(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(',', '');
  final d = double.tryParse(s);
  if (d == null) return null;
  final i = d.round();
  if ((d - i).abs() < 0.000001) return i;
  return d;
}

String _numToText(dynamic v) {
  if (v is int) return '$v';
  if (v is double) {
    final i = v.toInt();
    if ((v - i).abs() < 0.000001) return '$i';
    return v.toStringAsFixed(2);
  }
  if (v is num) return '$v';
  return '';
}

Future<void> showPricingQuickEditorSheet(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  try {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final allowed = await _isPricingAdminServer(uid);
  if (!allowed) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not authorized.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final primaryRef =
      FirebaseFirestore.instance.collection('app_config').doc('pricing');
  final legacyRef = FirebaseFirestore.instance.collection('app').doc('pricing');

  Map<String, dynamic> pricing;
  try {
    final snap = await primaryRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    if (snap.exists) {
      pricing = (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    } else {
      final old = await legacyRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      pricing = (old.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final usd =
      (pricing['usd'] is Map) ? (pricing['usd'] as Map).cast<String, dynamic>() : <String, dynamic>{};
  final ngn =
      (pricing['ngn'] is Map) ? (pricing['ngn'] as Map).cast<String, dynamic>() : <String, dynamic>{};

  final usdCreateFee = TextEditingController(
    text: _numToText(usd['createFee'] ?? usd['createLeagueFee']),
  );
  final usdAccessFee = TextEditingController(text: _numToText(usd['accessFee']));
  final usdCouponUnit = TextEditingController(text: _numToText(usd['couponUnit']));
  final usdPremiumFee = TextEditingController(text: _numToText(usd['premiumFee']));
  final usdPremiumDays = TextEditingController(text: _numToText(usd['premiumDurationDays']));
  final usdMlBasic = TextEditingController(
    text: _numToText(
      usd['masterLeagueBasicFee'] ?? usd['masterLinkBasicFee'] ?? usd['masterLinkFee'],
    ),
  );
  final usdMlPro = TextEditingController(
    text: _numToText(
      usd['masterLeagueProFee'] ?? usd['masterLinkProFee'] ?? usd['masterLinkFee'],
    ),
  );
  final usdMlElite = TextEditingController(
    text: _numToText(
      usd['masterLeagueEliteFee'] ?? usd['masterLinkEliteFee'] ?? usd['masterLinkFee'],
    ),
  );

  bool usdPremiumEnabled =
      (usd['premiumEnabled'] is bool) ? usd['premiumEnabled'] as bool : true;
  bool usdPaymentsEnabled =
      (usd['paymentsEnabled'] is bool) ? usd['paymentsEnabled'] as bool : true;
  bool usdFlutterwaveEnabled =
      (usd['flutterwaveEnabled'] is bool) ? usd['flutterwaveEnabled'] as bool : true;

  final ngnCreateFee = TextEditingController(
    text: _numToText(ngn['createFee'] ?? ngn['createLeagueFee']),
  );
  final ngnAccessFee = TextEditingController(text: _numToText(ngn['accessFee']));
  final ngnCouponUnit = TextEditingController(text: _numToText(ngn['couponUnit']));
  final ngnPremiumFee = TextEditingController(text: _numToText(ngn['premiumFee']));
  final ngnPremiumDays = TextEditingController(text: _numToText(ngn['premiumDurationDays']));
  final ngnMlBasic = TextEditingController(
    text: _numToText(
      ngn['masterLeagueBasicFee'] ?? ngn['masterLinkBasicFee'] ?? ngn['masterLinkFee'],
    ),
  );
  final ngnMlPro = TextEditingController(
    text: _numToText(
      ngn['masterLeagueProFee'] ?? ngn['masterLinkProFee'] ?? ngn['masterLinkFee'],
    ),
  );
  final ngnMlElite = TextEditingController(
    text: _numToText(
      ngn['masterLeagueEliteFee'] ?? ngn['masterLinkEliteFee'] ?? ngn['masterLinkFee'],
    ),
  );

  bool ngnPremiumEnabled =
      (ngn['premiumEnabled'] is bool) ? ngn['premiumEnabled'] as bool : true;
  bool ngnPaymentsEnabled =
      (ngn['paymentsEnabled'] is bool) ? ngn['paymentsEnabled'] as bool : true;
  bool ngnFlutterwaveEnabled =
      (ngn['flutterwaveEnabled'] is bool) ? ngn['flutterwaveEnabled'] as bool : true;

  bool saved = false;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final on = cs.onSurface;
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
      final isLight = theme.brightness == Brightness.light;

      bool busy = false;
      String? error;

      Widget field(String label, TextEditingController c, {String? helper}) {
        final fill = isLight ? Colors.white.withOpacity(0.52) : on.withOpacity(0.06);
        final border = isLight ? Colors.white.withOpacity(0.72) : on.withOpacity(0.12);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.primary.withOpacity(0.65),
                  width: 1.4,
                ),
              ),
            ),
          ),
        );
      }

      Widget sectionLabel(String text) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                color: on,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }

      Future<void> doSave(StateSetter setSheet) async {
        if (busy) return;

        final uc = _parseNum(usdCreateFee.text);
        final ua = _parseNum(usdAccessFee.text);
        final uu = _parseNum(usdCouponUnit.text);
        final upf = _parseNum(usdPremiumFee.text);
        final upd = _parseNum(usdPremiumDays.text);
        final ub = _parseNum(usdMlBasic.text);
        final up = _parseNum(usdMlPro.text);
        final ue = _parseNum(usdMlElite.text);

        final nc = _parseNum(ngnCreateFee.text);
        final na = _parseNum(ngnAccessFee.text);
        final nu = _parseNum(ngnCouponUnit.text);
        final npf = _parseNum(ngnPremiumFee.text);
        final npd = _parseNum(ngnPremiumDays.text);
        final nb = _parseNum(ngnMlBasic.text);
        final np = _parseNum(ngnMlPro.text);
        final ne = _parseNum(ngnMlElite.text);

        if (uc == null ||
            ua == null ||
            uu == null ||
            upf == null ||
            upd == null ||
            ub == null ||
            up == null ||
            ue == null ||
            nc == null ||
            na == null ||
            nu == null ||
            npf == null ||
            npd == null ||
            nb == null ||
            np == null ||
            ne == null) {
          setSheet(() => error = 'Enter valid numbers for all fields.');
          return;
        }

        setSheet(() {
          busy = true;
          error = null;
        });

        try {
          await ConnectivityService.instance.requireOnline(
            timeout: const Duration(seconds: 4),
          );
          final now = DateTime.now().millisecondsSinceEpoch;

          final payload = <String, dynamic>{
            'usd': <String, dynamic>{
              'createFee': uc,
              'accessFee': ua,
              'couponUnit': uu,
              'premiumFee': upf,
              'premiumDurationDays': upd.toInt(),
              'premiumEnabled': usdPremiumEnabled,
              'masterLeagueBasicFee': ub,
              'masterLeagueProFee': up,
              'masterLeagueEliteFee': ue,
              'masterLinkBasicFee': ub,
              'masterLinkProFee': up,
              'masterLinkEliteFee': ue,
              'masterLinkFee': up,
              'masterLeagueFee': up,
              'paymentsEnabled': usdPaymentsEnabled,
              'flutterwaveEnabled': usdFlutterwaveEnabled,
            },
            'ngn': <String, dynamic>{
              'createFee': nc,
              'accessFee': na,
              'couponUnit': nu,
              'premiumFee': npf,
              'premiumDurationDays': npd.toInt(),
              'premiumEnabled': ngnPremiumEnabled,
              'masterLeagueBasicFee': nb,
              'masterLeagueProFee': np,
              'masterLeagueEliteFee': ne,
              'masterLinkBasicFee': nb,
              'masterLinkProFee': np,
              'masterLinkEliteFee': ne,
              'masterLinkFee': np,
              'masterLeagueFee': np,
              'paymentsEnabled': ngnPaymentsEnabled,
              'flutterwaveEnabled': ngnFlutterwaveEnabled,
            },
            'updatedAtMs': now,
            'updatedBy': uid,
          };

          await primaryRef
              .set(payload, SetOptions(merge: true))
              .timeout(const Duration(seconds: 15));
          await legacyRef
              .set(payload, SetOptions(merge: true))
              .timeout(const Duration(seconds: 15));

          saved = true;
          if (ctx.mounted) Navigator.of(ctx).pop();
        } catch (e) {
          setSheet(() {
            busy = false;
            error =
                UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
          });
        }
      }

      final outlineSide = BorderSide(
        color: isLight ? Colors.white.withOpacity(0.72) : on.withOpacity(0.18),
      );

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Glass(
                borderRadius: 28,
                child: StatefulBuilder(
                  builder: (ctx, setSheet) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: on.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: cs.primary.withOpacity(0.14),
                                  border: Border.all(color: cs.primary.withOpacity(0.22)),
                                ),
                                child: Icon(Icons.price_change_rounded, color: cs.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Payment Control Center',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: on,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                                icon: Icon(Icons.close, color: on.withOpacity(0.55)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          sectionLabel('USD'),
                          field('League create fee', usdCreateFee),
                          field('League access fee', usdAccessFee),
                          field('Coupon unit', usdCouponUnit),
                          field('Premium fee', usdPremiumFee),
                          field('Premium duration (days)', usdPremiumDays),
                          SwitchListTile.adaptive(
                            value: usdPremiumEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => usdPremiumEnabled = v),
                            title: const Text('Premium enabled'),
                          ),
                          field('Master League Basic fee', usdMlBasic),
                          field('Master League Pro fee', usdMlPro),
                          field('Master League Elite fee', usdMlElite),
                          SwitchListTile.adaptive(
                            value: usdPaymentsEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => usdPaymentsEnabled = v),
                            title: const Text('Payments enabled'),
                          ),
                          SwitchListTile.adaptive(
                            value: usdFlutterwaveEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => usdFlutterwaveEnabled = v),
                            title: const Text('Flutterwave enabled'),
                          ),

                          const SizedBox(height: 8),
                          sectionLabel('NGN'),
                          field('League create fee', ngnCreateFee),
                          field('League access fee', ngnAccessFee),
                          field('Coupon unit', ngnCouponUnit),
                          field('Premium fee', ngnPremiumFee),
                          field('Premium duration (days)', ngnPremiumDays),
                          SwitchListTile.adaptive(
                            value: ngnPremiumEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => ngnPremiumEnabled = v),
                            title: const Text('Premium enabled'),
                          ),
                          field('Master League Basic fee', ngnMlBasic),
                          field('Master League Pro fee', ngnMlPro),
                          field('Master League Elite fee', ngnMlElite),
                          SwitchListTile.adaptive(
                            value: ngnPaymentsEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => ngnPaymentsEnabled = v),
                            title: const Text('Payments enabled'),
                          ),
                          SwitchListTile.adaptive(
                            value: ngnFlutterwaveEnabled,
                            onChanged: busy ? null : (v) => setSheet(() => ngnFlutterwaveEnabled = v),
                            title: const Text('Flutterwave enabled'),
                          ),

                          if ((error ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.error.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cs.error.withOpacity(0.25)),
                              ),
                              child: Text(
                                error!,
                                style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: busy ? null : () => doSave(setSheet),
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: const Text(
                                'Save',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                              style: OutlinedButton.styleFrom(
                                side: outlineSide,
                                foregroundColor: on.withOpacity(0.90),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  usdCreateFee.dispose();
  usdAccessFee.dispose();
  usdCouponUnit.dispose();
  usdPremiumFee.dispose();
  usdPremiumDays.dispose();
  usdMlBasic.dispose();
  usdMlPro.dispose();
  usdMlElite.dispose();

  ngnCreateFee.dispose();
  ngnAccessFee.dispose();
  ngnCouponUnit.dispose();
  ngnPremiumFee.dispose();
  ngnPremiumDays.dispose();
  ngnMlBasic.dispose();
  ngnMlPro.dispose();
  ngnMlElite.dispose();

  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pricing updated.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
