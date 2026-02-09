import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/remote_pricing_service.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/league_creation_payment_service.dart';
import '../utils/current_user.dart';

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

  // Coupons add-on
  bool _buyCoupons = false;
  int _couponCount = 1;

  // Admin subsidy: what percentage end users will pay (0..100).
  // Organizer pays the remainder at creation/upgrade time.
  int _userPaysPercent = 50;

  bool _initializedFromRoute = false;

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

  void _maybeInitFromRoute() {
    if (_initializedFromRoute) return;
    _initializedFromRoute = true;
    try {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final map = extra.cast<dynamic, dynamic>();
        // If organizer previously enabled coupons, reflect that in the toggle and quantity.
        final existingCouponsEnabled = map['existingCouponsEnabled'];
        if (existingCouponsEnabled is bool && existingCouponsEnabled) {
          _buyCoupons = true;
        }
        final existingCouponCount = map['existingCouponCount'];
        if (existingCouponCount is int && existingCouponCount > 0) {
          _couponCount = existingCouponCount;
          _buyCoupons = true;
        }
        // If previously set, try to reuse as a seed for "users pay %" (best-effort).
        final existingPct = map['existingCouponDiscountPercent'];
        if (existingPct is int) {
          _userPaysPercent = existingPct.clamp(0, 100);
        }
      }
    } catch (_) {
      // ignore
    }
    // Ensure sane defaults
    if (_couponCount <= 0) _couponCount = 1;
    _userPaysPercent = _userPaysPercent.clamp(0, 100);
  }

  String _money(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    _maybeInitFromRoute();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provider = ref.watch(leagueCreationPaymentServiceProvider);

    final addonsOnly = _addonsOnlyFromRouteExtra();

    return GlassScaffold(
      appBar: AppBar(
        title: Text(addonsOnly ? 'Upgrade payment' : l10n.tr('league_creation_payment_appbar_title')),
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

            // Pricing math:
            // baseFee = addonsOnly ? 0 : plan.createLeagueFee
            // couponSubtotal = plan.couponUnit * qty
            // if (couponSubtotal >= plan.couponThreshold && threshold != null) apply plan.couponDiscountPercent
            // organizerShare = discountedCouponSubtotal * (1 - userPays%)
            // total = baseFee + organizerShare
            final baseFee = addonsOnly ? 0.0 : plan.createLeagueFee;

            final int qty = (_buyCoupons ? _couponCount : 0).clamp(0, 100000);
            final rawCouponSubtotal = plan.couponUnit * qty;

            final bool thresholdConfigured = plan.couponThreshold != null && plan.couponThreshold! > 0;
            final bool discountApplies = thresholdConfigured && rawCouponSubtotal >= (plan.couponThreshold!);

            final double discountedCouponSubtotal = discountApplies
                ? (rawCouponSubtotal * ((100.0 - plan.couponDiscountPercent) / 100.0))
                : rawCouponSubtotal;

            final organizerPaysPercent = 100 - _userPaysPercent;
            final organizerShare = discountedCouponSubtotal * (organizerPaysPercent / 100.0);

            final total = baseFee + organizerShare;

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
                          Icons.payments_outlined,
                          color: cs.primary.withOpacity(0.95),
                          size: 46,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          addonsOnly ? 'Payment required to upgrade' : l10n.tr('league_creation_payment_required_title'),
                          style: titleStyle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Total: ${_money(total)} $currency\n\n'
                          '${addonsOnly ? 'Upgrade' : l10n.tr('league_creation_payment_explanation_prefix')} ${widget.leagueName}\n'
                          '${l10n.tr('league_creation_payment_provider_prefix')} ${provider.providerName}',
                          textAlign: TextAlign.center,
                          style: bodyStyle,
                        ),
                        const SizedBox(height: 16),

                        // ----------------------------
                        // Coupons (optional)
                        // ----------------------------
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
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
                                                _couponCount = 1;
                                              }
                                            });
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Coupon unit: ${_money(plan.couponUnit)} $currency. '
                                '${thresholdConfigured ? '30% discount when subtotal ≥ ${_money(plan.couponThreshold!)} $currency.' : 'Bulk discount not configured.'}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.65),
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
                                    Icon(Icons.confirmation_number_outlined, color: cs.onSurface.withOpacity(0.70), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_couponCount coupons • Unit: ${_money(plan.couponUnit)} $currency'
                                        '${discountApplies ? ' • 30% discount applied' : ''}',
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
                                                _couponCount = (_couponCount - 10).clamp(1, 100000);
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
                                                _couponCount = (_couponCount + 10).clamp(1, 100000);
                                              });
                                            },
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: _couponCount.toDouble().clamp(1, 100000),
                                  min: 1,
                                  max: 100000,
                                  divisions: 1000,
                                  label: '$_couponCount',
                                  onChanged: _processing
                                      ? null
                                      : (v) {
                                          final rounded = v.round();
                                          setState(() => _couponCount = rounded.clamp(1, 100000));
                                        },
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Admin subsidy (who pays what)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined, color: cs.onSurface.withOpacity(0.70), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Users pay: $_userPaysPercent% • Admin pays: ${100 - _userPaysPercent}%',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.72),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: _userPaysPercent.toDouble(),
                                  min: 0,
                                  max: 100,
                                  divisions: 20, // steps of 5%
                                  label: '$_userPaysPercent%',
                                  onChanged: _processing
                                      ? null
                                      : (v) {
                                          final rounded = (v / 5).round() * 5;
                                          setState(() => _userPaysPercent = rounded.clamp(0, 100));
                                        },
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ----------------------------
                        // Breakdown
                        // ----------------------------
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
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
                                'League creation fee',
                                '${_money(baseFee)} $currency',
                              ),
                              _kv(
                                context,
                                'Coupons subtotal',
                                '${_money(rawCouponSubtotal)} $currency',
                              ),
                              _kv(
                                context,
                                discountApplies ? 'Threshold discount (30%)' : 'Threshold discount',
                                discountApplies ? '- ${_money(rawCouponSubtotal - discountedCouponSubtotal)} $currency' : '—',
                              ),
                              _kv(
                                context,
                                'Organizer share (${100 - _userPaysPercent}%)',
                                '${_money(organizerShare)} $currency',
                              ),
                              const Divider(),
                              _kvStrong(
                                context,
                                'Total payable now',
                                '${_money(total)} $currency',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _processing ? null : () => context.pop<LeagueCreationPaymentResult?>(null),
                                child: Text(l10n.tr('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _processing
                                    ? null
                                    : () async {
                                        setState(() => _processing = true);
                                        try {
                                          final userId = await CurrentUser.getOrCreateUserId();

                                          final result = await provider.collectLeagueCreationFee(
                                            context: context,
                                            userId: userId,
                                            leagueName: widget.leagueName,
                                            addonsOnly: addonsOnly,
                                            // viewers removed: keep 0 for backward compatibility
                                            viewerCapacity: 0,
                                            buyCouponsForParticipants: _buyCoupons,
                                            // TEMP: pass "users pay %" in couponDiscountPercent until model/UI migration completes
                                            couponDiscountPercent: _userPaysPercent,
                                            couponCount: _buyCoupons ? _couponCount : 0,
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
                                    : Text(l10n.tr('league_creation_payment_pay_continue')),
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
