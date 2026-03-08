import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics/analytics_rollup_service.dart';
import '../../core/services/app_admins_service.dart';

class DeveloperAnalyticsDashboardScreen extends StatefulWidget {
  const DeveloperAnalyticsDashboardScreen({super.key});

  @override
  State<DeveloperAnalyticsDashboardScreen> createState() => _DeveloperAnalyticsDashboardScreenState();
}

class _DeveloperAnalyticsDashboardScreenState extends State<DeveloperAnalyticsDashboardScreen> {
  bool _busy = false;
  String? _error;

  bool _isAdmin() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return AppAdminsService.instance.isPricingAdminUid(uid);
  }

  Future<void> _rebuild() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AnalyticsRollupService.instance.rebuild(daysBack: 30);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rollups rebuilt (last 30 days).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_isAdmin()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Developer Analytics')),
        body: Center(
          child: Text(
            'Not authorized.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final firestore = FirebaseFirestore.instance;
    final summaryRef = firestore.collection('analytics_summary').doc('global');
    final daysQuery = firestore.collection('revenue_by_day').orderBy('dayId', descending: true).limit(30);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Analytics'),
        actions: [
          IconButton(
            tooltip: 'Manage Admins',
            onPressed: () => context.push('/admin/pricing-admins'),
            icon: const Icon(Icons.admin_panel_settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: summaryRef.snapshots(),
          builder: (context, sumSnap) {
            final summary = sumSnap.data?.data() ?? <String, dynamic>{};
            final totals = (summary['totals'] is Map) ? (summary['totals'] as Map).cast<String, dynamic>() : <String, dynamic>{};

            final successful = (totals['successfulPayments'] is num) ? (totals['successfulPayments'] as num).toInt() : 0;
            final failed = (totals['failedPayments'] is num) ? (totals['failedPayments'] as num).toInt() : 0;
            final leaguesCreated = (totals['leaguesCreated'] is num) ? (totals['leaguesCreated'] as num).toInt() : 0;
            final couponsSold = (totals['couponsSold'] is num) ? (totals['couponsSold'] as num).toInt() : 0;

            final revenueMap = (totals['revenue'] is Map) ? (totals['revenue'] as Map).cast<String, dynamic>() : <String, dynamic>{};
            final revNGN = (revenueMap['NGN'] is num) ? (revenueMap['NGN'] as num).toDouble() : 0.0;
            final revUSD = (revenueMap['USD'] is num) ? (revenueMap['USD'] as num).toDouble() : 0.0;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: daysQuery.snapshots(),
              builder: (context, daysSnap) {
                final dayDocs = daysSnap.data?.docs ?? const [];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.error.withOpacity(0.25)),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _busy ? null : _rebuild,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Rebuild rollups (30 days)', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 12),
                    _metricRow(
                      context,
                      left: _metricCard(context, 'Revenue (NGN)', _money('NGN', revNGN)),
                      right: _metricCard(context, 'Revenue (USD)', _money('USD', revUSD)),
                    ),
                    const SizedBox(height: 12),
                    _metricRow(
                      context,
                      left: _metricCard(context, 'Successful payments', '$successful'),
                      right: _metricCard(context, 'Failed payments', '$failed'),
                    ),
                    const SizedBox(height: 12),
                    _metricRow(
                      context,
                      left: _metricCard(context, 'Coupons sold', '$couponsSold'),
                      right: _metricCard(context, 'Leagues created', '$leaguesCreated'),
                    ),
                    const SizedBox(height: 18),
                    Text('Revenue by day (last 30)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    if (dayDocs.isEmpty)
                      Text(
                        'No data yet. Tap “Rebuild rollups”.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      ...dayDocs.map((d) {
                        final data = d.data();
                        final dayId = (data['dayId'] ?? d.id).toString();
                        final rev = (data['revenue'] is Map) ? (data['revenue'] as Map).cast<String, dynamic>() : <String, dynamic>{};
                        final ngn = (rev['NGN'] is num) ? (rev['NGN'] as num).toDouble() : 0.0;
                        final usd = (rev['USD'] is num) ? (rev['USD'] as num).toDouble() : 0.0;

                        return Card(
                          elevation: 0,
                          color: cs.onSurface.withOpacity(0.04),
                          child: ListTile(
                            title: Text(dayId, style: const TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text('NGN ${_fmt(ngn)} • USD ${_fmt(usd)}'),
                          ),
                        );
                      }),
                    const SizedBox(height: 18),
                    Text('Revenue by product type', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    _productTypeTable(context, summary),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _fmt(num v) => v.toStringAsFixed(2);

  static String _money(String currency, double amount) {
    if (currency.toUpperCase() == 'NGN') return '₦${amount.toStringAsFixed(0)}';
    return '\$${amount.toStringAsFixed(2)}';
  }

  Widget _metricRow(BuildContext context, {required Widget left, required Widget right}) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _metricCard(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withOpacity(0.12)),
        color: cs.onSurface.withOpacity(0.035),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _productTypeTable(BuildContext context, Map<String, dynamic> summary) {
    final cs = Theme.of(context).colorScheme;
    final byProduct = (summary['byProductType'] is Map) ? (summary['byProductType'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    if (byProduct.isEmpty) {
      return Text(
        'No data yet. Tap “Rebuild rollups”.',
        style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600),
      );
    }

    final keys = byProduct.keys.toList()..sort();

    return Column(
      children: keys.map((k) {
        final m = (byProduct[k] is Map) ? (byProduct[k] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final count = (m['count'] is num) ? (m['count'] as num).toInt() : 0;
        final units = (m['units'] is num) ? (m['units'] as num).toInt() : 0;
        final rev = (m['revenue'] is Map) ? (m['revenue'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final ngn = (rev['NGN'] is num) ? (rev['NGN'] as num).toDouble() : 0.0;
        final usd = (rev['USD'] is num) ? (rev['USD'] as num).toDouble() : 0.0;

        final subtitle = units > 0
            ? 'count: $count • units: $units • NGN ${_fmt(ngn)} • USD ${_fmt(usd)}'
            : 'count: $count • NGN ${_fmt(ngn)} • USD ${_fmt(usd)}';

        return Card(
          elevation: 0,
          color: cs.onSurface.withOpacity(0.04),
          child: ListTile(
            title: Text(k, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(subtitle),
          ),
        );
      }).toList(),
    );
  }
}
