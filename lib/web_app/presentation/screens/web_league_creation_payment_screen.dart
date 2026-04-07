import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/leagues/logic/league_creation_payment_service.dart';
import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../../features/master_leagues/logic/master_league_pricing_service.dart';

class WebLeagueCreationPaymentScreen extends ConsumerStatefulWidget {
  const WebLeagueCreationPaymentScreen({
    super.key,
    required this.leagueName,
  });

  final String leagueName;

  @override
  ConsumerState<WebLeagueCreationPaymentScreen> createState() =>
      _WebLeagueCreationPaymentScreenState();
}

class _WebLeagueCreationPaymentScreenState
    extends ConsumerState<WebLeagueCreationPaymentScreen> {
  bool _processing = false;

  bool _buyCoupons = false;
  int _couponCount = 1;
  int _discountPercent = 50;

  bool _couponCodeCustomMode = false;
  final TextEditingController _couponCodeBase = TextEditingController();

  int _existingCouponCount = 0;

  bool _initializedFromRoute = false;

  MasterLeaguePlan _selectedUpgradePlan = MasterLeaguePlan.pro;
  PlanDuration _selectedUpgradeDuration = PlanDuration.threeMonths;

  @override
  void dispose() {
    _couponCodeBase.dispose();
    super.dispose();
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

  MasterLeaguePlan _upgradePlanFromRouteExtra() {
    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();
        final raw = (map['upgradePlan'] ?? '').toString().trim().toLowerCase();
        return MasterLeaguePlan.fromString(raw);
      }
    } catch (_) {}
    return MasterLeaguePlan.pro;
  }

  PlanDuration _upgradeDurationFromRouteExtra() {
    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();
        final raw = (map['upgradeDuration'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return PlanDuration.fromString(raw);
      }
    } catch (_) {}
    return PlanDuration.threeMonths;
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
        } else if (existingCouponsEnabled is int &&
            existingCouponsEnabled == 1) {
          _buyCoupons = true;
        }

        final existingCouponCount = map['existingCouponCount'];
        if (existingCouponCount is int && existingCouponCount > 0) {
          _existingCouponCount = existingCouponCount;
        } else if (existingCouponCount is num &&
            existingCouponCount.toInt() > 0) {
          _existingCouponCount = existingCouponCount.toInt();
        }

        final existingPct = map['existingCouponDiscountPercent'];
        if (existingPct is int) {
          _discountPercent = existingPct.clamp(0, 100);
        } else if (existingPct is num) {
          _discountPercent = existingPct.toInt().clamp(0, 100);
        }

        if (premiumUpgrade) {
          _selectedUpgradePlan = _upgradePlanFromRouteExtra();
          _selectedUpgradeDuration = _upgradeDurationFromRouteExtra();
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

  Widget _flatPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: child,
    );
  }

  Widget _softPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: child,
    );
  }

  Widget _buildPlanTile({
    required MasterLeaguePlan plan,
    required ThemeData theme,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final brightness = theme.brightness;

    final fill = selected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : AppTheme.searchBackground(brightness);

    final border = selected
        ? AppTheme.limeAccentDark
        : AppTheme.searchOutline(brightness);

    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? AppTheme.limeAccentDark
                  : AppTheme.secondaryText(brightness),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plan.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                      ),
                      if (plan.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF22C55E).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  const Color(0xFF22C55E).withOpacity(0.28),
                            ),
                          ),
                          child: const Text(
                            'POPULAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF22C55E),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondaryText(brightness),
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationTile({
    required PlanDuration duration,
    required ThemeData theme,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final brightness = theme.brightness;

    final fill = selected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : AppTheme.searchBackground(brightness);

    final border = selected
        ? AppTheme.limeAccentDark
        : AppTheme.searchOutline(brightness);

    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? AppTheme.limeAccentDark
                  : AppTheme.secondaryText(brightness),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                duration.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryText(brightness),
                ),
              ),
            ),
            if (duration.discountLabel.isNotEmpty)
              Text(
                duration.discountLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF22C55E),
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvStrong(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            v,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(
    BuildContext context, {
    required String title,
    required String body,
    required IconData icon,
    required Color tint,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return _flatPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withOpacity(0.12),
            ),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeInitFromRoute();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final provider = ref.watch(leagueCreationPaymentServiceProvider);

    final addonsOnly = _addonsOnlyFromRouteExtra();
    final premiumUpgrade = _premiumUpgradeModeFromRouteExtra();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      return GlassScaffold(
        useBubbles: false,
        appBar: AppBar(
          title: Text(
            premiumUpgrade
                ? 'Upgrade Organizer Plan'
                : (addonsOnly
                    ? 'Upgrade payment'
                    : l10n.tr('league_creation_payment_appbar_title')),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _flatPanel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.login,
                        color: AppTheme.limeAccentDark,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to continue. Payments must be tied to your Firebase account.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed:
                            () => context.pop<LeagueCreationPaymentResult?>(null),
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
      useBubbles: false,
      appBar: AppBar(
        title: Text(
          premiumUpgrade
              ? 'Upgrade Organizer Plan'
              : (addonsOnly
                  ? 'Upgrade payment'
                  : l10n.tr('league_creation_payment_appbar_title')),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<RemotePricingPlan>(
          future: RemotePricingService.instance.getPlanForLocale(
            Localizations.maybeLocaleOf(context),
          ),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  'Failed to load pricing. Please try again.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            if (!snap.hasData) {
              return Center(
                child: CircularProgressIndicator(
                  color: AppTheme.limeAccentDark,
                ),
              );
            }

            final plan = snap.data!;
            final currency = plan.currency;

            return FutureBuilder<PlanPriceInfo?>(
              future: premiumUpgrade
                  ? MasterLeaguePricingService().getPlanPrice(
                      plan: _selectedUpgradePlan,
                      duration: _selectedUpgradeDuration,
                      locale: Localizations.maybeLocaleOf(context),
                    )
                  : Future<PlanPriceInfo?>.value(null),
              builder: (context, premiumSnap) {
                final premiumPrice = premiumSnap.data;

                final baseFee = premiumUpgrade
                    ? (premiumPrice?.amount ?? 0).toDouble()
                    : (addonsOnly ? 0.0 : plan.createLeagueFee);

                final premiumCurrency = premiumUpgrade
                    ? ((premiumPrice?.currency.trim().isNotEmpty ?? false)
                        ? premiumPrice!.currency.trim().toUpperCase()
                        : currency)
                    : currency;

                final int qty =
                    (_buyCoupons && !premiumUpgrade ? _couponCount : 0)
                        .clamp(0, 100000);
                final int disc = _discountPercent.clamp(0, 100);

                final int discForPurchase =
                    (qty > 0 && disc <= 0) ? 50 : disc;

                final pricing = RemotePricingService.instance
                    .computeOrganizerCouponPricing(
                  plan: plan,
                  couponCount: qty,
                  discountPercent: discForPurchase,
                );

                final rawCouponSubtotal = pricing.rawSubtotal;
                final discountedCouponSubtotal = pricing.discountedSubtotal;
                final bool bulkDiscountApplied = pricing.bulkDiscountApplied;

                final total = baseFee + discountedCouponSubtotal;

                final userPaysAtRedemption =
                    plan.accessFee * ((100 - discForPurchase) / 100.0);

                final bool thresholdConfigured =
                    plan.couponThreshold != null && plan.couponThreshold! > 0;

                final double minCoupon = _buyCoupons ? 1 : (addonsOnly ? 0 : 1);
                final double couponSliderValue =
                    _couponCount.toDouble().clamp(minCoupon, 100000.0);

                final String preview = _previewCode(
                  customMode: _couponCodeCustomMode,
                  base: _couponCodeBase.text,
                  discountPercent: discForPurchase,
                );

                final bool customInvalid =
                    _couponCodeCustomMode && _customNameInvalid(_couponCodeBase.text);

                final headerTitle = premiumUpgrade
                    ? 'Choose Organizer Plan'
                    : (addonsOnly
                        ? 'Payment required to upgrade'
                        : l10n.tr('league_creation_payment_required_title'));

                final headerBody = premiumUpgrade
                    ? 'Upgrade your organizer account to continue creating more leagues and unlock larger organizer capacity.\n\n'
                        'Selected plan: ${_selectedUpgradePlan.displayName}\n'
                        'Duration: ${_selectedUpgradeDuration.displayName}\n'
                        'Plan fee: ${_money(baseFee)} $premiumCurrency\n'
                        'Provider: ${provider.providerName}'
                    : 'Total: ${_money(total)} $currency\n\n'
                        '${addonsOnly ? 'Upgrade' : l10n.tr('league_creation_payment_explanation_prefix')} ${widget.leagueName}\n'
                        '${l10n.tr('league_creation_payment_provider_prefix')} ${provider.providerName}';

                final mainContent = Column(
                  children: [
                    _headerCard(
                      context,
                      title: headerTitle,
                      body: headerBody,
                      icon: premiumUpgrade
                          ? Icons.workspace_premium_rounded
                          : Icons.payments_outlined,
                      tint: premiumUpgrade
                          ? const Color(0xFFF59E0B)
                          : AppTheme.limeAccentDark,
                    ),
                    if (premiumUpgrade) ...[
                      const SizedBox(height: 14),
                      _flatPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose plan',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildPlanTile(
                              plan: MasterLeaguePlan.pro,
                              theme: theme,
                              selected: _selectedUpgradePlan == MasterLeaguePlan.pro,
                              onTap: () => setState(
                                () => _selectedUpgradePlan = MasterLeaguePlan.pro,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildPlanTile(
                              plan: MasterLeaguePlan.elite,
                              theme: theme,
                              selected:
                                  _selectedUpgradePlan == MasterLeaguePlan.elite,
                              onTap: () => setState(
                                () => _selectedUpgradePlan = MasterLeaguePlan.elite,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _flatPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose duration',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDurationTile(
                              duration: PlanDuration.threeMonths,
                              theme: theme,
                              selected: _selectedUpgradeDuration ==
                                  PlanDuration.threeMonths,
                              onTap: () => setState(
                                () => _selectedUpgradeDuration =
                                    PlanDuration.threeMonths,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDurationTile(
                              duration: PlanDuration.sixMonths,
                              theme: theme,
                              selected:
                                  _selectedUpgradeDuration == PlanDuration.sixMonths,
                              onTap: () => setState(
                                () => _selectedUpgradeDuration =
                                    PlanDuration.sixMonths,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDurationTile(
                              duration: PlanDuration.yearly,
                              theme: theme,
                              selected:
                                  _selectedUpgradeDuration == PlanDuration.yearly,
                              onTap: () => setState(
                                () => _selectedUpgradeDuration =
                                    PlanDuration.yearly,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _flatPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plan benefits',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedUpgradePlan == MasterLeaguePlan.pro
                                  ? '• Create more than 3 total league cards\n'
                                      '• Unlock Pro organizer plan\n'
                                      '• Up to 5 master leagues\n'
                                      '• Up to 9 competitions inside each master league'
                                  : '• Create more than 3 total league cards\n'
                                      '• Unlock Elite organizer plan\n'
                                      '• Unlimited master leagues\n'
                                      '• Unlimited competitions',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondaryText(brightness),
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!premiumUpgrade) ...[
                      const SizedBox(height: 14),
                      _flatPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Coupons (optional)',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.primaryText(brightness),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  activeColor: AppTheme.limeAccentDark,
                                  value: _buyCoupons,
                                  onChanged: _processing
                                      ? null
                                      : (v) {
                                          setState(() {
                                            _buyCoupons = v;

                                            if (!v) {
                                              _couponCount =
                                                  addonsOnly ? 0 : 1;
                                            } else {
                                              if (_couponCount <= 0) {
                                                _couponCount = 1;
                                              }
                                              if (_discountPercent <= 0) {
                                                _discountPercent = 50;
                                              }
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
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Full coupon unit (access fee): ${_money(plan.couponUnit)} $currency.\n'
                              'You pay only the discount portion now: unit × (discount%).',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondaryText(brightness),
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
                                color: AppTheme.secondaryText(brightness),
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            if (_buyCoupons) ...[
                              const SizedBox(height: 12),
                              Text(
                                'How many coupons do you want to buy?',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.confirmation_number_outlined,
                                    color: AppTheme.secondaryText(brightness),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${addonsOnly ? 'Additional coupons' : 'Coupons'}: $_couponCount'
                                      '${bulkDiscountApplied ? ' • Bulk discount applied' : ''}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppTheme.secondaryText(brightness),
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
                                              _couponCount =
                                                  next.clamp(1, 100000);
                                              if (_discountPercent <= 0) {
                                                _discountPercent = 50;
                                              }
                                            });
                                          },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Increase',
                                    onPressed: _processing
                                        ? null
                                        : () {
                                            setState(() {
                                              final next = (_couponCount + 10);
                                              _couponCount =
                                                  next.clamp(1, 100000);
                                              if (_discountPercent <= 0) {
                                                _discountPercent = 50;
                                              }
                                            });
                                          },
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                activeColor: AppTheme.limeAccentDark,
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
                                          _couponCount =
                                              rounded.clamp(1, 100000);
                                          if (_discountPercent <= 0) {
                                            _discountPercent = 50;
                                          }
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Discount percent (for users)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.percent,
                                    color: AppTheme.secondaryText(brightness),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Discount: $discForPurchase% • Users pay at redemption: ${_money(_round2(userPaysAtRedemption))} $currency',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppTheme.secondaryText(brightness),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                activeColor: AppTheme.limeAccentDark,
                                value: _discountPercent.toDouble(),
                                min: 5,
                                max: 100,
                                divisions: 19,
                                label: '$_discountPercent%',
                                onChanged: _processing
                                    ? null
                                    : (v) {
                                        final rounded =
                                            (v / 5).round() * 5;
                                        setState(() => _discountPercent =
                                            rounded.clamp(5, 100));
                                      },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Coupon code type (optional)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text(
                                      'Random',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    selected: !_couponCodeCustomMode,
                                    selectedColor: AppTheme.limeAccent,
                                    backgroundColor:
                                        AppTheme.searchBackground(brightness),
                                    side: BorderSide(
                                      color: !_couponCodeCustomMode
                                          ? AppTheme.limeAccentDark
                                          : AppTheme.searchOutline(brightness),
                                    ),
                                    labelStyle: TextStyle(
                                      color: !_couponCodeCustomMode
                                          ? AppTheme.darkText
                                          : AppTheme.tabInactiveText(brightness),
                                    ),
                                    onSelected: _processing
                                        ? null
                                        : (_) => setState(() =>
                                            _couponCodeCustomMode = false),
                                  ),
                                  const SizedBox(width: 10),
                                  ChoiceChip(
                                    label: const Text(
                                      'Custom',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    selected: _couponCodeCustomMode,
                                    selectedColor: AppTheme.limeAccent,
                                    backgroundColor:
                                        AppTheme.searchBackground(brightness),
                                    side: BorderSide(
                                      color: _couponCodeCustomMode
                                          ? AppTheme.limeAccentDark
                                          : AppTheme.searchOutline(brightness),
                                    ),
                                    labelStyle: TextStyle(
                                      color: _couponCodeCustomMode
                                          ? AppTheme.darkText
                                          : AppTheme.tabInactiveText(brightness),
                                    ),
                                    onSelected: _processing
                                        ? null
                                        : (_) => setState(() =>
                                            _couponCodeCustomMode = true),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_couponCodeCustomMode) ...[
                                TextField(
                                  controller: _couponCodeBase,
                                  enabled: !_processing,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9 _-]'),
                                    ),
                                    LengthLimitingTextInputFormatter(24),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Custom name (example: BARCA)',
                                    prefixIcon: const Icon(Icons.edit),
                                    errorText: customInvalid
                                        ? 'Invalid name (no "/" and max 24 chars).'
                                        : null,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Custom name is used for display/preview; it must not contain "/".',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppTheme.secondaryText(brightness),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              Text(
                                'Preview: $preview',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );

                final summaryContent = _flatPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _kv(
                        context,
                        premiumUpgrade
                            ? '${_selectedUpgradePlan.displayName} plan fee'
                            : 'League creation fee',
                        '${_money(baseFee)} ${premiumUpgrade ? premiumCurrency : currency}',
                      ),
                      if (premiumUpgrade)
                        _kv(
                          context,
                          'Duration',
                          _selectedUpgradeDuration.displayName,
                        ),
                      if (!premiumUpgrade) ...[
                        _kv(
                          context,
                          'Coupons subtotal (organizer pays)',
                          '${_money(rawCouponSubtotal)} $currency',
                        ),
                        _kv(
                          context,
                          bulkDiscountApplied
                              ? 'Bulk discount (${_money(plan.couponDiscountPercent)}%)'
                              : 'Bulk discount',
                          bulkDiscountApplied
                              ? '- ${_money(rawCouponSubtotal - discountedCouponSubtotal)} $currency'
                              : '—',
                        ),
                      ],
                      const Divider(),
                      _kvStrong(
                        context,
                        'Total payable now',
                        '${_money(total)} ${premiumUpgrade ? premiumCurrency : currency}',
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _processing
                                  ? null
                                  : () => context.pop<LeagueCreationPaymentResult?>(
                                        null,
                                      ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: AppTheme.cardBorder(brightness),
                                ),
                                foregroundColor:
                                    AppTheme.primaryText(brightness),
                              ),
                              child: Text(l10n.tr('common_cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.limeAccent,
                                foregroundColor: AppTheme.darkText,
                              ),
                              onPressed: (_processing || customInvalid)
                                  ? null
                                  : () async {
                                      if (!premiumUpgrade) {
                                        if (_buyCoupons && _couponCount <= 0) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                  'Select at least 1 coupon to buy.'),
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          );
                                          return;
                                        }

                                        if (_buyCoupons &&
                                            _couponCount > 0 &&
                                            _discountPercent <= 0) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                  'Set a discount above 0% to buy coupons.'),
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          );
                                          return;
                                        }
                                      }

                                      setState(() => _processing = true);
                                      try {
                                        final userId =
                                            await _requireAuthUidForPayment();

                                        final result = await provider
                                            .collectLeagueCreationFee(
                                          context: context,
                                          userId: userId,
                                          leagueName: premiumUpgrade
                                              ? 'Organizer Plan: ${_selectedUpgradePlan.displayName}'
                                              : widget.leagueName,
                                          addonsOnly: false,
                                          premiumUpgrade: premiumUpgrade,
                                          selectedPlan: premiumUpgrade
                                              ? _selectedUpgradePlan
                                              : null,
                                          viewerCapacity: 0,
                                          buyCouponsForParticipants:
                                              premiumUpgrade
                                                  ? false
                                                  : _buyCoupons,
                                          couponDiscountPercent: premiumUpgrade
                                              ? 0
                                              : _discountPercent,
                                          couponCount: premiumUpgrade
                                              ? 0
                                              : (_buyCoupons ? _couponCount : 0),
                                        );

                                        if (!mounted) return;

                                        if (result.success) {
                                          context.pop<LeagueCreationPaymentResult>(
                                              result);
                                          return;
                                        }

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              result.errorMessage ??
                                                  l10n.tr(
                                                      'leagues_payment_failed'),
                                            ),
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${l10n.tr('league_creation_payment_failed_prefix')} $e',
                                            ),
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        );
                                      } finally {
                                        if (mounted) {
                                          setState(() => _processing = false);
                                        }
                                      }
                                    },
                              child: _processing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.darkText,
                                      ),
                                    )
                                  : Text(
                                      premiumUpgrade
                                          ? 'Upgrade Now'
                                          : l10n.tr(
                                              'league_creation_payment_pay_continue',
                                            ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );

                return SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWide ? 1160 : 620),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: mainContent),
                                const SizedBox(width: 16),
                                Expanded(flex: 4, child: summaryContent),
                              ],
                            )
                          : Column(
                              children: [
                                mainContent,
                                const SizedBox(height: 16),
                                summaryContent,
                              ],
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
}
