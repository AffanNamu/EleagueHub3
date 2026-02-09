import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_pricing_admin_service.dart';

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

  // NGN
  final _ngnCreate = TextEditingController();
  final _ngnAccess = TextEditingController();
  final _ngnCouponUnit = TextEditingController();
  final _ngnThreshold = TextEditingController();
  final _ngnDiscount = TextEditingController();
  bool _ngnViewers = false;

  // USD
  final _usdCreate = TextEditingController();
  final _usdAccess = TextEditingController();
  final _usdCouponUnit = TextEditingController();
  final _usdThreshold = TextEditingController();
  final _usdDiscount = TextEditingController();
  bool _usdViewers = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  @override
  void dispose() {
    _ngnCreate.dispose();
    _ngnAccess.dispose();
    _ngnCouponUnit.dispose();
    _ngnThreshold.dispose();
    _ngnDiscount.dispose();

    _usdCreate.dispose();
    _usdAccess.dispose();
    _usdCouponUnit.dispose();
    _usdThreshold.dispose();
    _usdDiscount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await _svc.fetch();
      final ngn = (doc['ngn'] as Map).cast<String, dynamic>();
      final usd = (doc['usd'] as Map).cast<String, dynamic>();

      setState(() {
        _ngnCreate.text = '${ngn['createFee'] ?? ''}';
        _ngnAccess.text = '${ngn['accessFee'] ?? ''}';
        _ngnCouponUnit.text = '${ngn['couponUnit'] ?? ''}';
        _ngnThreshold.text = ngn['couponThreshold'] == null ? '' : '${ngn['couponThreshold']}';
        _ngnDiscount.text = '${ngn['couponDiscountPercent'] ?? ''}';
        _ngnViewers = (ngn['viewersEnabled'] is bool) ? ngn['viewersEnabled'] as bool : false;

        _usdCreate.text = '${usd['createFee'] ?? ''}';
        _usdAccess.text = '${usd['accessFee'] ?? ''}';
        _usdCouponUnit.text = '${usd['couponUnit'] ?? ''}';
        _usdThreshold.text = usd['couponThreshold'] == null ? '' : '${usd['couponThreshold']}';
        _usdDiscount.text = '${usd['couponDiscountPercent'] ?? ''}';
        _usdViewers = (usd['viewersEnabled'] is bool) ? usd['viewersEnabled'] as bool : false;

        _loading = false;
        _error = null;
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
      Map<String, dynamic> _collectNgn() => {
            'createFee': _parse(_ngnCreate.text),
            'accessFee': _parse(_ngnAccess.text),
            'couponUnit': _parse(_ngnCouponUnit.text),
            'couponThreshold': _parseOrNull(_ngnThreshold.text),
            'couponDiscountPercent': _parse(_ngnDiscount.text),
            'viewersEnabled': _ngnViewers,
          };

      Map<String, dynamic> _collectUsd() => {
            'createFee': _parse(_usdCreate.text),
            'accessFee': _parse(_usdAccess.text),
            'couponUnit': _parse(_usdCouponUnit.text),
            'couponThreshold': _parseOrNull(_usdThreshold.text),
            'couponDiscountPercent': _parse(_usdDiscount.text),
            'viewersEnabled': _usdViewers,
          };

      await _svc.save(ngn: _collectNgn(), usd: _collectUsd());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pricing updated'),
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

  double? _parseOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return _parse(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pricing Admin')),
        body: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing Admin')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.error.withOpacity(0.35)),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _currencyCard(
                  title: 'NGN plan',
                  children: [
                    _rowNum('Create fee (NGN)', _ngnCreate),
                    _rowNum('Access fee (NGN)', _ngnAccess),
                    _rowNum('Coupon unit (NGN)', _ngnCouponUnit),
                    _rowNumAllowNull('Coupon threshold (NGN, empty = none)', _ngnThreshold),
                    _rowNum('Threshold discount (%)', _ngnDiscount),
                    SwitchListTile.adaptive(
                      value: _ngnViewers,
                      onChanged: (v) => setState(() => _ngnViewers = v),
                      title: const Text('Viewers enabled (legacy; keep off)'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _currencyCard(
                  title: 'USD plan',
                  children: [
                    _rowNum('Create fee (USD)', _usdCreate),
                    _rowNum('Access fee (USD)', _usdAccess),
                    _rowNum('Coupon unit (USD)', _usdCouponUnit),
                    _rowNumAllowNull('Coupon threshold (USD, empty = none)', _usdThreshold),
                    _rowNum('Threshold discount (%)', _usdDiscount),
                    SwitchListTile.adaptive(
                      value: _usdViewers,
                      onChanged: (v) => setState(() => _usdViewers = v),
                      title: const Text('Viewers enabled (legacy; keep off)'),
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: Owner-only. Rules enforce writes only for authorized UIDs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currencyCard({required String title, required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
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
}
