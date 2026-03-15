import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_pricing_admin_service.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';

class PricingAdminScreen extends StatefulWidget {
  const PricingAdminScreen({super.key});

  @override
  State<PricingAdminScreen> createState() => _PricingAdminScreenState();
}

class _PricingAdminScreenState extends State<PricingAdminScreen> {
  final _svc = AppPricingAdminService();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _ngnCreate = TextEditingController();
  final _ngnAccess = TextEditingController();
  final _ngnCouponUnit = TextEditingController();
  final _ngnThreshold = TextEditingController();
  final _ngnDiscount = TextEditingController();
  bool _ngnViewers = false;
  final _ngnPremiumFee = TextEditingController();
  final _ngnPremiumDays = TextEditingController();
  bool _ngnPremiumEnabled = true;
  final _ngnMlBasic = TextEditingController();
  final _ngnMlPro = TextEditingController();
  final _ngnMlElite = TextEditingController();
  bool _ngnPaymentsEnabled = true;
  bool _ngnFlutterwaveEnabled = true;

  final _usdCreate = TextEditingController();
  final _usdAccess = TextEditingController();
  final _usdCouponUnit = TextEditingController();
  final _usdThreshold = TextEditingController();
  final _usdDiscount = TextEditingController();
  bool _usdViewers = false;
  final _usdPremiumFee = TextEditingController();
  final _usdPremiumDays = TextEditingController();
  bool _usdPremiumEnabled = true;
  final _usdMlBasic = TextEditingController();
  final _usdMlPro = TextEditingController();
  final _usdMlElite = TextEditingController();
  bool _usdPaymentsEnabled = true;
  bool _usdFlutterwaveEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ngnCreate.dispose();
    _ngnAccess.dispose();
    _ngnCouponUnit.dispose();
    _ngnThreshold.dispose();
    _ngnDiscount.dispose();
    _ngnPremiumFee.dispose();
    _ngnPremiumDays.dispose();
    _ngnMlBasic.dispose();
    _ngnMlPro.dispose();
    _ngnMlElite.dispose();

    _usdCreate.dispose();
    _usdAccess.dispose();
    _usdCouponUnit.dispose();
    _usdThreshold.dispose();
    _usdDiscount.dispose();
    _usdPremiumFee.dispose();
    _usdPremiumDays.dispose();
    _usdMlBasic.dispose();
    _usdMlPro.dispose();
    _usdMlElite.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final doc = await _svc.fetch();
      final ngn = (doc['ngn'] as Map).cast<String, dynamic>();
      final usd = (doc['usd'] as Map).cast<String, dynamic>();

      setState(() {
        _ngnCreate.text = '${ngn['createFee'] ?? ''}';
        _ngnAccess.text = '${ngn['accessFee'] ?? ''}';
        _ngnCouponUnit.text = '${ngn['couponUnit'] ?? ''}';
        _ngnThreshold.text =
            ngn['couponThreshold'] == null ? '' : '${ngn['couponThreshold']}';
        _ngnDiscount.text = '${ngn['couponDiscountPercent'] ?? ''}';
        _ngnViewers =
            (ngn['viewersEnabled'] is bool) ? ngn['viewersEnabled'] as bool : false;
        _ngnPremiumFee.text = '${ngn['premiumFee'] ?? '5000'}';
        _ngnPremiumDays.text = '${ngn['premiumDurationDays'] ?? '30'}';
        _ngnPremiumEnabled =
            (ngn['premiumEnabled'] is bool) ? ngn['premiumEnabled'] as bool : true;
        _ngnMlBasic.text = '${ngn['masterLeagueBasicFee'] ?? ngn['masterLinkBasicFee'] ?? ''}';
        _ngnMlPro.text = '${ngn['masterLeagueProFee'] ?? ngn['masterLinkProFee'] ?? ngn['masterLinkFee'] ?? ''}';
        _ngnMlElite.text = '${ngn['masterLeagueEliteFee'] ?? ngn['masterLinkEliteFee'] ?? ''}';
        _ngnPaymentsEnabled =
            (ngn['paymentsEnabled'] is bool) ? ngn['paymentsEnabled'] as bool : true;
        _ngnFlutterwaveEnabled =
            (ngn['flutterwaveEnabled'] is bool) ? ngn['flutterwaveEnabled'] as bool : true;

        _usdCreate.text = '${usd['createFee'] ?? ''}';
        _usdAccess.text = '${usd['accessFee'] ?? ''}';
        _usdCouponUnit.text = '${usd['couponUnit'] ?? ''}';
        _usdThreshold.text =
            usd['couponThreshold'] == null ? '' : '${usd['couponThreshold']}';
        _usdDiscount.text = '${usd['couponDiscountPercent'] ?? ''}';
        _usdViewers =
            (usd['viewersEnabled'] is bool) ? usd['viewersEnabled'] as bool : false;
        _usdPremiumFee.text = '${usd['premiumFee'] ?? '9.99'}';
        _usdPremiumDays.text = '${usd['premiumDurationDays'] ?? '30'}';
        _usdPremiumEnabled =
            (usd['premiumEnabled'] is bool) ? usd['premiumEnabled'] as bool : true;
        _usdMlBasic.text = '${usd['masterLeagueBasicFee'] ?? usd['masterLinkBasicFee'] ?? ''}';
        _usdMlPro.text = '${usd['masterLeagueProFee'] ?? usd['masterLinkProFee'] ?? usd['masterLinkFee'] ?? ''}';
        _usdMlElite.text = '${usd['masterLeagueEliteFee'] ?? usd['masterLinkEliteFee'] ?? ''}';
        _usdPaymentsEnabled =
            (usd['paymentsEnabled'] is bool) ? usd['paymentsEnabled'] as bool : true;
        _usdFlutterwaveEnabled =
            (usd['flutterwaveEnabled'] is bool) ? usd['flutterwaveEnabled'] as bool : true;

        _loading = false;
      });
    } on FirebaseException catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load pricing: ${e.message ?? e.code}';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load pricing: $e';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      Map<String, dynamic> collectNgn() => {
            'createFee': _parse(_ngnCreate.text),
            'accessFee': _parse(_ngnAccess.text),
            'couponUnit': _parse(_ngnCouponUnit.text),
            'couponThreshold': _parseOrNull(_ngnThreshold.text),
            'couponDiscountPercent': _parse(_ngnDiscount.text),
            'viewersEnabled': _ngnViewers,
            'premiumFee': _parse(_ngnPremiumFee.text),
            'premiumDurationDays': _parseInt(_ngnPremiumDays.text),
            'premiumEnabled': _ngnPremiumEnabled,
            'masterLeagueBasicFee': _parse(_ngnMlBasic.text),
            'masterLeagueProFee': _parse(_ngnMlPro.text),
            'masterLeagueEliteFee': _parse(_ngnMlElite.text),
            'paymentsEnabled': _ngnPaymentsEnabled,
            'flutterwaveEnabled': _ngnFlutterwaveEnabled,
          };

      Map<String, dynamic> collectUsd() => {
            'createFee': _parse(_usdCreate.text),
            'accessFee': _parse(_usdAccess.text),
            'couponUnit': _parse(_usdCouponUnit.text),
            'couponThreshold': _parseOrNull(_usdThreshold.text),
            'couponDiscountPercent': _parse(_usdDiscount.text),
            'viewersEnabled': _usdViewers,
            'premiumFee': _parse(_usdPremiumFee.text),
            'premiumDurationDays': _parseInt(_usdPremiumDays.text),
            'premiumEnabled': _usdPremiumEnabled,
            'masterLeagueBasicFee': _parse(_usdMlBasic.text),
            'masterLeagueProFee': _parse(_usdMlPro.text),
            'masterLeagueEliteFee': _parse(_usdMlElite.text),
            'paymentsEnabled': _usdPaymentsEnabled,
            'flutterwaveEnabled': _usdFlutterwaveEnabled,
          };

      await _svc.save(ngn: collectNgn(), usd: collectUsd());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment control updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      setState(() => _error = 'Failed to save pricing: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _error = 'Failed to save pricing: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double _parse(String s) {
    final v = double.tryParse(s.trim());
    if (v == null) throw StateError('Invalid number: "$s"');
    return v;
  }

  int _parseInt(String s) {
    final v = int.tryParse(s.trim());
    if (v == null) throw StateError('Invalid integer: "$s"');
    if (v < 1) throw StateError('Duration must be at least 1 day');
    return v;
  }

  double? _parseOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return _parse(t);
  }

  Widget _sectionDivider(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.onSurface.withOpacity(0.12))),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: cs.onSurface.withOpacity(0.12))),
        ],
      ),
    );
  }

  Widget _currencyCard({required String title, required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.onSurface.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _rowNum(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.numbers),
        ),
      ),
    );
  }

  Widget _rowNumAllowNull(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Leave empty to disable threshold-based discount',
          prefixIcon: const Icon(Icons.numbers),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return GlassScaffold(
        appBar: AppBar(title: const Text('Payment Control Center')),
        body: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Payment Control Center'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Glass(
              borderRadius: 28,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.error.withOpacity(0.35)),
                      ),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _currencyCard(
                    title: 'NGN',
                    children: [
                      _rowNum('League create fee (NGN)', _ngnCreate),
                      _rowNum('League access fee (NGN)', _ngnAccess),
                      _rowNum('Coupon unit (NGN)', _ngnCouponUnit),
                      _rowNumAllowNull('Coupon threshold (NGN)', _ngnThreshold),
                      _rowNum('Threshold discount (%)', _ngnDiscount),
                      SwitchListTile.adaptive(
                        value: _ngnViewers,
                        onChanged: (v) => setState(() => _ngnViewers = v),
                        title: const Text('Viewers enabled (legacy)'),
                      ),
                      _sectionDivider('Premium'),
                      _rowNum('Premium fee (NGN)', _ngnPremiumFee),
                      _rowNum('Premium duration (days)', _ngnPremiumDays),
                      SwitchListTile.adaptive(
                        value: _ngnPremiumEnabled,
                        onChanged: (v) => setState(() => _ngnPremiumEnabled = v),
                        title: const Text('Premium enabled'),
                      ),
                      _sectionDivider('Master League'),
                      _rowNum('Basic fee (NGN)', _ngnMlBasic),
                      _rowNum('Pro fee (NGN)', _ngnMlPro),
                      _rowNum('Elite fee (NGN)', _ngnMlElite),
                      _sectionDivider('Provider flags'),
                      SwitchListTile.adaptive(
                        value: _ngnPaymentsEnabled,
                        onChanged: (v) => setState(() => _ngnPaymentsEnabled = v),
                        title: const Text('Payments enabled'),
                      ),
                      SwitchListTile.adaptive(
                        value: _ngnFlutterwaveEnabled,
                        onChanged: (v) => setState(() => _ngnFlutterwaveEnabled = v),
                        title: const Text('Flutterwave enabled'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _currencyCard(
                    title: 'USD',
                    children: [
                      _rowNum('League create fee (USD)', _usdCreate),
                      _rowNum('League access fee (USD)', _usdAccess),
                      _rowNum('Coupon unit (USD)', _usdCouponUnit),
                      _rowNumAllowNull('Coupon threshold (USD)', _usdThreshold),
                      _rowNum('Threshold discount (%)', _usdDiscount),
                      SwitchListTile.adaptive(
                        value: _usdViewers,
                        onChanged: (v) => setState(() => _usdViewers = v),
                        title: const Text('Viewers enabled (legacy)'),
                      ),
                      _sectionDivider('Premium'),
                      _rowNum('Premium fee (USD)', _usdPremiumFee),
                      _rowNum('Premium duration (days)', _usdPremiumDays),
                      SwitchListTile.adaptive(
                        value: _usdPremiumEnabled,
                        onChanged: (v) => setState(() => _usdPremiumEnabled = v),
                        title: const Text('Premium enabled'),
                      ),
                      _sectionDivider('Master League'),
                      _rowNum('Basic fee (USD)', _usdMlBasic),
                      _rowNum('Pro fee (USD)', _usdMlPro),
                      _rowNum('Elite fee (USD)', _usdMlElite),
                      _sectionDivider('Provider flags'),
                      SwitchListTile.adaptive(
                        value: _usdPaymentsEnabled,
                        onChanged: (v) => setState(() => _usdPaymentsEnabled = v),
                        title: const Text('Payments enabled'),
                      ),
                      SwitchListTile.adaptive(
                        value: _usdFlutterwaveEnabled,
                        onChanged: (v) => setState(() => _usdFlutterwaveEnabled = v),
                        title: const Text('Flutterwave enabled'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _load,
                          child: const Text('Reload'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text(
                            'Save',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
