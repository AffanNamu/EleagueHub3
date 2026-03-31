import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/league_creation_payment_service.dart';

class LeagueCreationPaymentScreen extends ConsumerStatefulWidget {
  const LeagueCreationPaymentScreen({
    super.key,
    required this.leagueName,
  });

  final String leagueName;

  @override
  ConsumerState<LeagueCreationPaymentScreen> createState() => _LeagueCreationPaymentScreenState();
}

class _LeagueCreationPaymentScreenState extends ConsumerState<LeagueCreationPaymentScreen> {
  bool _processing = false;

  bool _buyCoupons = false;
  int _couponCount = 1;
  int _discountPercent = 50;

  bool _couponCodeCustomMode = false;
  final TextEditingController _couponCodeBase = TextEditingController();

  int _existingCouponCount = 0;

  bool _initializedFromRoute = false;

  @override
  void dispose() {
    _couponCodeBase.dispose();
    super.dispose();
  }

  Color _panelFill(ThemeData theme) {
    if (theme.brightness == Brightness.light) {
      return Colors.white.withOpacity(0.42);
    }
    return theme.colorScheme.onSurface.withOpacity(0.04);
  }

  Color _panelBorder(ThemeData theme, {Color? accent}) {
    final cs = theme.colorScheme;
    if (theme.brightness == Brightness.light) {
      final a = accent ?? cs.primary;
      return Color.alphaBlend(a.withOpacity(0.12), Colors.white.withOpacity(0.78));
    }
    return cs.onSurface.withOpacity(0.10);
  }

  List<BoxShadow>? _panelShadow(ThemeData theme, {Color? tint}) {
    if (theme.brightness != Brightness.light) return null;
    final c = tint ?? const Color(0xFFB4D2FF);
    return <BoxShadow>[
      BoxShadow(
        color: c.withOpacity(0.22),
        blurRadius: 30,
        offset: const Offset(0, 18),
      ),
    ];
  }

  bool _addonsOnlyFromRouteExtra() {
    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();
        final v = map['addonsOnly'];
        if (v is bool) return v;
        if (v is int) return v == 1;
      }
    } catch (_) {}
    return false;
  }

  bool _premiumUpgradeModeFromRouteExtra() {
    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();
        final v = map['premiumUpgrade'];
        if (v is bool) return v;
        if (v is int) return v == 1;
      }
    } catch (_) {}
    return false;
  }

  void _maybeInitFromRoute() {
    if (_initializedFromRoute) return;
    _initializedFromRoute = true;

    final addonsOnly = _addonsOnlyFromRouteExtra();
    final premiumUpgrade = _premiumUpgradeModeFromRouteExtra();

    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();

        final existingCouponsEnabled = map['existingCouponsEnabled'];
        if (existingCouponsEnabled is bool && existingCouponsEnabled) {
          _buyCoupons = true;
        } else if (existingCouponsEnabled is int && existingCouponsEnabled == 1) {
          _buyCoupons = true;
        }

        final existingCouponCount = map['existingCouponCount'];
        if (existingCouponCount is int && existingCouponCount > 0) {
          _existingCouponCount = existingCouponCount;
        } else if (existingCouponCount is num && existingCouponCount.toInt() > 0) {
          _existingCouponCount = existingCouponCount.toInt();
        }

        final existingPct = map['existingCouponDiscountPercent'];
        if (existingPct is int) {
          _discountPercent = existingPct.clamp(0, 100);
        } else if (existingPct is num) {
          _discountPercent = existingPct.toInt().clamp(0, 100);
        }

        if (premiumUpgrade) {
          _buyCoupons = false;
          _couponCount = 0;
        } else if (addonsOnly) {
          _couponCount = 0;
        } else {
          if (_existingCouponCount > 0) {
            _couponCount = _existingCouponCount;
            _buyCoupons = true;
          } else {
            _couponCount = 1;
          }
        }

        if (_buyCoupons && _couponCount > 0 && _discountPercent <= 0) {
          _discountPercent = 50;
        }
      }
    } catch (_) {}

    _couponCount = _couponCount.clamp(0, 100000);
    _discountPercent = _discountPercent.clamp(0, 100);
  }

  String _money(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  Future<String> _requireAuthUidForPayment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isNotEmpty) return uid.trim();
    throw StateError('Sign in required.');
  }

  String _previewCode({
    required bool customMode,
    required String base,
    required int discountPercent,
  }) {
    final pct = discountPercent.clamp(0, 100);
    if (!customMode) return 'ESLXXXXXXXXXXXX';

    final normalized = base
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'[^A-Z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final name = normalized.isEmpty ? 'NAME' : normalized;
    return 'ESL_${name}_$pct%';
  }

  bool _customNameInvalid(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.contains('/')) return true;
    if (t.length > 24) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _maybeInitFromRoute();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provider = ref.watch(leagueCreationPaymentServiceProvider);

    final addonsOnly = _addonsOnlyFromRouteExtra();
    final premiumUpgrade = _premiumUpgradeModeFromRouteExtra();

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(
            premiumUpgrade
                ? 'Upgrade to Premium'
                : (addonsOnly ? 'Upgrade payment' : l10n.tr('league_creation_payment_appbar_title')),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, color: cs.primary, size: 44),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to continue. Payments must be tied to your Firebase account.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.pop<LeagueCreationPaymentResult?>(null),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          premiumUpgrade
              ? 'Upgrade to Premium'
              : (addonsOnly ? 'Upgrade payment' : l10n.tr('league_creation_payment_appbar_title')),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<RemotePricingPlan>(
          future: RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context)),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  'Failed to load pricing. Please try again.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            if (!snap.hasData) {
              return Center(child: CircularProgressIndicator(color: cs.primary));
            }

            final plan = snap.data!;
            final currency = plan.currency;

            final baseFee = premiumUpgrade
                ? plan.createLeagueFee
                : (addonsOnly ? 0.0 : plan.createLeagueFee);

            final int qty = (_buyCoupons && !premiumUpgrade ? _couponCount : 0).clamp(0, 100000);
            final int disc = _discountPercent.clamp(0, 100);

            final int discForPurchase = (qty > 0 && disc <= 0) ? 50 : disc;

            final pricing = RemotePricingService.instance.computeOrganizerCouponPricing(
              plan: plan,
              couponCount: qty,
              discountPercent: discForPurchase,
            );

            final rawCouponSubtotal = pricing.rawSubtotal;
            final discountedCouponSubtotal = pricing.discountedSubtotal;
            final bool bulkDiscountApplied = pricing.bulkDiscountApplied;

            final total = baseFee + discountedCouponSubtotal;

            final userPaysAtRedemption = plan.accessFee * ((100 - discForPurchase) / 100.0);

            final titleStyle = theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            );

            final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.72),
              fontWeight: FontWeight.w600,
              height: 1.35,
            );

            final qtyLabel = addonsOnly ? 'Additional coupons' : 'Coupons';

            final bool thresholdConfigured = plan.couponThreshold != null && plan.couponThreshold! > 0;

            final double minCoupon = _buyCoupons ? 1 : (addonsOnly ? 0 : 1);
            final double couponSliderValue = _couponCount.toDouble().clamp(minCoupon, 100000.0);

            final String preview = _previewCode(
              customMode: _couponCodeCustomMode,
              base: _couponCodeBase.text,
              discountPercent: discForPurchase,
            );

            final bool customInvalid = _couponCodeCustomMode && _customNameInvalid(_couponCodeBase.text);

            final chipBg = theme.brightness == Brightness.light ? Colors.white.withOpacity(0.34) : cs.onSurface.withOpacity(0.06);
            final chipBorder =
                theme.brightness == Brightness.light ? Colors.white.withOpacity(0.72) : cs.onSurface.withOpacity(0.12);

            final headerTitle = premiumUpgrade
                ? 'Upgrade to Premium'
                : (addonsOnly ? 'Payment required to upgrade' : l10n.tr('league_creation_payment_required_title'));

            final headerBody = premiumUpgrade
                ? 'Upgrade your organizer account to continue creating more leagues.\n\n'
                  'Premium unlock fee: ${_money(baseFee)} $currency\n'
                  'Account: ${widget.leagueName}\n'
                  'Provider: ${provider.providerName}'
                : 'Total: ${_money(total)} $currency\n\n'
                  '${addonsOnly ? 'Upgrade' : l10n.tr('league_creation_payment_explanation_prefix')} ${widget.leagueName}\n'
                  '${l10n.tr('league_creation_payment_provider_prefix')} ${provider.providerName}';

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Glass(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          premiumUpgrade ? Icons.workspace_premium_rounded : Icons.payments_outlined,
                          color: premiumUpgrade
                              ? const Color(0xFFF59E0B)
                              : cs.primary.withOpacity(0.95),
                          size: 46,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          headerTitle,
                          style: titleStyle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          headerBody,
                          textAlign: TextAlign.center,
                          style: bodyStyle,
                        ),
                        const SizedBox(height: 16),

                        if (premiumUpgrade)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withOpacity(0.24),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Premium benefits',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Create more than 3 total league cards\n'
                                  '• Keep all existing leagues active\n'
                                  '• Continue growing as an organizer\n'
                                  '• Optionally purchase coupons later',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.72),
                                    fontWeight: FontWeight.w700,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (!premiumUpgrade) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _panelFill(theme),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _panelBorder(theme)),
                              boxShadow: _panelShadow(theme, tint: cs.primary),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Coupons (optional)',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: _buyCoupons,
                                      onChanged: _processing
                                          ? null
                                          : (v) {
                                              setState(() {
                                                _buyCoupons = v;

                                                if (!v) {
                                                  _couponCount = addonsOnly ? 0 : 1;
                                                } else {
                                                  if (_couponCount <= 0) {
                                                    _couponCount = 1;
                                                  }
                                                  if (_discountPercent <= 0) _discountPercent = 50;
                                                }
                                              });
                                            },
                                    ),
                                  ],
                                ),
                                if (addonsOnly && _existingCouponCount > 0) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Already purchased: $_existingCouponCount',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.70),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Full coupon unit (access fee): ${_money(plan.couponUnit)} $currency.\n'
                                  'You pay only the discount portion now: unit × (discount%).',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.65),
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  thresholdConfigured
                                      ? 'Bulk discount: ${_money(plan.couponDiscountPercent)}% when coupon subtotal ≥ ${_money(plan.couponThreshold!)} $currency.'
                                      : 'Bulk discount not configured.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.60),
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                                if (_buyCoupons) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'How many coupons do you want to buy?',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.confirmation_number_outlined,
                                        color: cs.onSurface.withOpacity(0.70),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$qtyLabel: $_couponCount'
                                          '${bulkDiscountApplied ? ' • Bulk discount applied' : ''}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.onSurface.withOpacity(0.72),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Decrease',
                                        onPressed: _processing
                                            ? null
                                            : () {
                                                setState(() {
                                                  final next = (_couponCount - 10);
                                                  _couponCount = next.clamp(1, 100000);
                                                  if (_discountPercent <= 0) _discountPercent = 50;
                                                });
                                              },
                                        icon: const Icon(Icons.remove_circle_outline),
                                      ),
                                      IconButton(
                                        tooltip: 'Increase',
                                        onPressed: _processing
                                            ? null
                                            : () {
                                                setState(() {
                                                  final next = (_couponCount + 10);
                                                  _couponCount = next.clamp(1, 100000);
                                                  if (_discountPercent <= 0) _discountPercent = 50;
                                                });
                                              },
                                        icon: const Icon(Icons.add_circle_outline),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: couponSliderValue,
                                    min: minCoupon,
                                    max: 100000.0,
                                    divisions: 1000,
                                    label: '$_couponCount',
                                    onChanged: _processing
                                        ? null
                                        : (v) {
                                            final rounded = v.round();
                                            setState(() {
                                              _couponCount = rounded.clamp(1, 100000);
                                              if (_discountPercent <= 0) _discountPercent = 50;
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Discount percent (for users)',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.percent, color: cs.onSurface.withOpacity(0.70), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Discount: $discForPurchase% • Users pay at redemption: ${_money(_round2(userPaysAtRedemption))} $currency',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.onSurface.withOpacity(0.72),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: _discountPercent.toDouble(),
                                    min: 5,
                                    max: 100,
                                    divisions: 19,
                                    label: '$_discountPercent%',
                                    onChanged: _processing
                                        ? null
                                        : (v) {
                                            final rounded = (v / 5).round() * 5;
                                            setState(() => _discountPercent = rounded.clamp(5, 100));
                                          },
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Coupon code type (optional)',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Random', style: TextStyle(fontWeight: FontWeight.w800)),
                                        selected: !_couponCodeCustomMode,
                                        selectedColor: cs.primary.withOpacity(0.18),
                                        backgroundColor: chipBg,
                                        side: BorderSide(color: !_couponCodeCustomMode ? cs.primary.withOpacity(0.35) : chipBorder),
                                        onSelected: _processing ? null : (_) => setState(() => _couponCodeCustomMode = false),
                                      ),
                                      const SizedBox(width: 10),
                                      ChoiceChip(
                                        label: const Text('Custom', style: TextStyle(fontWeight: FontWeight.w800)),
                                        selected: _couponCodeCustomMode,
                                        selectedColor: cs.primary.withOpacity(0.18),
                                        backgroundColor: chipBg,
                                        side: BorderSide(color: _couponCodeCustomMode ? cs.primary.withOpacity(0.35) : chipBorder),
                                        onSelected: _processing ? null : (_) => setState(() => _couponCodeCustomMode = true),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_couponCodeCustomMode) ...[
                                    TextField(
                                      controller: _couponCodeBase,
                                      enabled: !_processing,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 _-]')),
                                        LengthLimitingTextInputFormatter(24),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Custom name (example: BARCA)',
                                        prefixIcon: const Icon(Icons.edit),
                                        errorText: customInvalid ? 'Invalid name (no "/" and max 24 chars).' : null,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Custom name is used for display/preview; it must not contain "/".',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.65),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                  Text(
                                    'Preview: $preview',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.65),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _panelFill(theme),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _panelBorder(theme)),
                            boxShadow: _panelShadow(theme),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Summary',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _kv(
                                context,
                                premiumUpgrade ? 'Premium upgrade fee' : 'League creation fee',
                                '${_money(baseFee)} $currency',
                              ),
                              if (!premiumUpgrade) ...[
                                _kv(context, 'Coupons subtotal (organizer pays)', '${_money(rawCouponSubtotal)} $currency'),
                                _kv(
                                  context,
                                  bulkDiscountApplied ? 'Bulk discount (${_money(plan.couponDiscountPercent)}%)' : 'Bulk discount',
                                  bulkDiscountApplied ? '- ${_money(rawCouponSubtotal - discountedCouponSubtotal)} $currency' : '—',
                                ),
                              ],
                              const Divider(),
                              _kvStrong(context, 'Total payable now', '${_money(total)} $currency'),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _processing ? null : () => context.pop<LeagueCreationPaymentResult?>(null),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: theme.brightness == Brightness.light
                                        ? Colors.white.withOpacity(0.72)
                                        : cs.onSurface.withOpacity(0.18),
                                  ),
                                  foregroundColor: cs.onSurface.withOpacity(0.85),
                                ),
                                child: Text(l10n.tr('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: (_processing || customInvalid)
                                    ? null
                                    : () async {
                                        if (!premiumUpgrade) {
                                          if (_buyCoupons && _couponCount <= 0) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: const Text('Select at least 1 coupon to buy.'),
                                                backgroundColor: cs.error,
                                              ),
                                            );
                                            return;
                                          }

                                          if (_buyCoupons && _couponCount > 0 && _discountPercent <= 0) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: const Text('Set a discount above 0% to buy coupons.'),
                                                backgroundColor: cs.error,
                                              ),
                                            );
                                            return;
                                          }
                                        }

                                        setState(() => _processing = true);
                                        try {
                                          final userId = await _requireAuthUidForPayment();

                                          final result = await provider.collectLeagueCreationFee(
                                            context: context,
                                            userId: userId,
                                            leagueName: widget.leagueName,
                                            addonsOnly: premiumUpgrade ? false : addonsOnly,
                                            viewerCapacity: 0,
                                            buyCouponsForParticipants: premiumUpgrade ? false : _buyCoupons,
                                            couponDiscountPercent: premiumUpgrade ? 0 : _discountPercent,
                                            couponCount: premiumUpgrade ? 0 : (_buyCoupons ? _couponCount : 0),
                                          );

                                          if (!mounted) return;

                                          if (result.success) {
                                            context.pop<LeagueCreationPaymentResult>(result);
                                            return;
                                          }

                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
                                              backgroundColor: cs.error,
                                            ),
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${l10n.tr('league_creation_payment_failed_prefix')} $e'),
                                              backgroundColor: cs.error,
                                            ),
                                          );
                                        } finally {
                                          if (mounted) setState(() => _processing = false);
                                        }
                                      },
                                child: _processing
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.onPrimary,
                                        ),
                                      )
                                    : Text(
                                        premiumUpgrade
                                            ? 'Upgrade Now'
                                            : l10n.tr('league_creation_payment_pay_continue'),
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
            );
          },
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.85),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvStrong(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            v,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
