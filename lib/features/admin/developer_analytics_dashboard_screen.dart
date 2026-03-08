import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/analytics/analytics_rollup_service.dart';
import '../../core/services/app_admins_service.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';

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
        const SnackBar(content: Text('Rollups rebuilt (last 30 days).'), behavior: SnackBarBehavior.floating),
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
      return GlassScaffold(
        appBar: AppBar(title: const Text('Developer Analytics')),
        body: Center(
          child: Glass(
            borderRadius: 22,
            child: Text(
              'Not authorized.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      );
    }

    final firestore = FirebaseFirestore.instance;
    final summaryRef = firestore.collection('analytics_summary').doc('global');
    final daysQuery = firestore.collection('revenue_by_day').orderBy('dayId', descending: true).limit(30);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Developer Analytics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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

                return SingleChildScrollView(
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
                              _errorBox(context, _error!),
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

                            const SizedBox(height: 14),

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
                            const SizedBox(height: 10),

                            if (dayDocs.isEmpty)
                              Text(
                                'No data yet. Tap “Rebuild rollups”.',
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700),
                              )
                            else
                              ...dayDocs.map((d) {
                                final data = d.data();
                                final dayId = (data['dayId'] ?? d.id).toString();
                                final rev = (data['revenue'] is Map) ? (data['revenue'] as Map).cast<String, dynamic>() : <String, dynamic>{};
                                final ngn = (rev['NGN'] is num) ? (rev['NGN'] as num).toDouble() : 0.0;
                                final usd = (rev['USD'] is num) ? (rev['USD'] as num).toDouble() : 0.0;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Glass(
                                    borderRadius: 18,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(dayId, style: const TextStyle(fontWeight: FontWeight.w900)),
                                        ),
                                        Text('₦${ngn.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                        const SizedBox(width: 12),
                                        Text('\$${usd.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                );
                              }),

                            const SizedBox(height: 10),
                            Text('Revenue by product type', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            _productTypeList(context, summary),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withOpacity(0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
      ),
    );
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.70),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productTypeList(BuildContext context, Map<String, dynamic> summary) {
    final cs = Theme.of(context).colorScheme;
    final byProduct = (summary['byProductType'] is Map) ? (summary['byProductType'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    if (byProduct.isEmpty) {
      return Text(
        'No data yet.',
        style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700),
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
            ? 'count: $count • units: $units • NGN ${ngn.toStringAsFixed(2)} • USD ${usd.toStringAsFixed(2)}'
            : 'count: $count • NGN ${ngn.toStringAsFixed(2)} • USD ${usd.toStringAsFixed(2)}';

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Glass(
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _money(String currency, double amount) {
    if (currency.toUpperCase() == 'NGN') return '₦${amount.toStringAsFixed(0)}';
    return '\$${amount.toStringAsFixed(2)}';
  }
}
