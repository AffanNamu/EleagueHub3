import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/league_creation_payment_service.dart';
import '../utils/current_user.dart';

enum _CouponMode {
  freeAccess,
  percentageDiscount,
}

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

  // OPTIONAL paid add-on
  int _viewerCapacity = 0;

  // OPTIONAL: coupon purchase add-on (generated after payment + league creation)
  bool _buyCouponsForParticipants = false;
  _CouponMode _couponMode = _CouponMode.freeAccess;
  int _couponPercent = 20; // Used only when _couponMode == percentageDiscount (5..90)

  // NEW: coupon quantity to purchase/cover during league creation payment.
  int _couponCount = 0;

  double _parseAmount(String raw) => double.tryParse(raw.trim()) ?? 0;

  String _money(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  int _effectiveCouponPercent() {
    if (!_buyCouponsForParticipants) return 0;
    if (_couponMode == _CouponMode.freeAccess) return 100;
    final v = _couponPercent;
    if (v < 5) return 5;
    if (v > 90) return 90;
    return v;
  }

  int _effectiveCouponCount() {
    if (!_buyCouponsForParticipants) return 0;
    // Enforce at least 1 coupon if coupons are enabled (prevents enabling coupons with 0 fee).
    return _couponCount <= 0 ? 1 : _couponCount;
  }

  double _addonWithBulkDiscount({
    required double unitPrice,
    required int count,
  }) {
    if (count <= 0) return 0;
    final raw = unitPrice * count;
    // Rule: above 100 => 20% discount on that add-on portion only.
    if (count > 100) return raw * 0.8;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provider = ref.watch(leagueCreationPaymentServiceProvider);

    final locale = Localizations.maybeLocaleOf(context);
    final pricing = FlutterwaveConfig.pricingForLocale(locale);

    // Pricing:
    // totalAmount = baseLeagueFee + (viewerCapacity × viewerUnitPrice [bulk discount]) + (couponCount × couponUnitPrice [bulk discount])
    //
    // Note: couponUnitPrice == viewerUnitPrice (pricing.viewLeagueAmount), as requested.
    final baseFee = _parseAmount(pricing.createLeagueAmount);
    final unitPrice = _parseAmount(pricing.viewLeagueAmount);

    final viewersAddon = _addonWithBulkDiscount(unitPrice: unitPrice, count: _viewerCapacity);
    final couponsAddon = _addonWithBulkDiscount(unitPrice: unitPrice, count: _effectiveCouponCount());

    final total = baseFee + viewersAddon + (_buyCouponsForParticipants ? couponsAddon : 0);

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

    final couponsSummary = !_buyCouponsForParticipants
        ? 'Coupons: None'
        : (_effectiveCouponPercent() >= 100 ? 'Coupons: Free access (100%)' : 'Coupons: ${_effectiveCouponPercent()}% discount');

    final viewerDiscountNote = _viewerCapacity > 100 ? ' (20% bulk discount applied)' : '';
    final couponDiscountNote = (_buyCouponsForParticipants && _effectiveCouponCount() > 100) ? ' (20% bulk discount applied)' : '';

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_creation_payment_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                      l10n.tr('league_creation_payment_required_title'),
                      style: titleStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${l10n.tr('league_creation_payment_amount_prefix')} ${_money(total)} ${pricing.currency}\n\n'
                      '${l10n.tr('league_creation_payment_explanation_prefix')} ${widget.leagueName}\n'
                      '${l10n.tr('league_creation_payment_provider_prefix')} ${provider.providerName}\n'
                      '$couponsSummary',
                      textAlign: TextAlign.center,
                      style: bodyStyle,
                    ),
                    const SizedBox(height: 16),

                    // ----------------------------
                    // Viewer Capacity (optional)
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
                            'Viewer Capacity (optional)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Viewers are separate from participants. This only affects price. Above 100 viewers gets 20% discount.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.visibility, color: cs.onSurface.withOpacity(0.70), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$_viewerCapacity viewers • Unit: ${_money(unitPrice)} ${pricing.currency}$viewerDiscountNote',
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
                                          _viewerCapacity = (_viewerCapacity - 10).clamp(0, 500);
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
                                          _viewerCapacity = (_viewerCapacity + 10).clamp(0, 500);
                                        });
                                      },
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                          Slider(
                            value: _viewerCapacity.toDouble(),
                            min: 0,
                            max: 500,
                            divisions: 50, // step of 10
                            label: '$_viewerCapacity',
                            onChanged: _processing
                                ? null
                                : (v) {
                                    setState(() => _viewerCapacity = (v / 10).round() * 10);
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add-on: ${_money(viewersAddon)} ${pricing.currency}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ----------------------------
                    // Coupons for participants (optional)
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
                                  'Coupons for participants (optional)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                value: _buyCouponsForParticipants,
                                onChanged: _processing
                                    ? null
                                    : (v) {
                                        setState(() {
                                          _buyCouponsForParticipants = v;
                                          if (!v) {
                                            _couponMode = _CouponMode.freeAccess;
                                            _couponCount = 0;
                                          } else {
                                            // Keep it safe: if toggled on and count is 0, show 1 in UI.
                                            if (_couponCount <= 0) _couponCount = 1;
                                          }
                                        });
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Coupon unit fee equals viewer fee. Above 100 coupons gets 20% discount on the coupon portion.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (_buyCouponsForParticipants) ...[
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
                                    '${_effectiveCouponCount()} coupons • Unit: ${_money(unitPrice)} ${pricing.currency}$couponDiscountNote',
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
                                            _couponCount = (_couponCount - 10).clamp(1, 500);
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
                                            _couponCount = (_couponCount + 10).clamp(1, 500);
                                          });
                                        },
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            Slider(
                              value: _effectiveCouponCount().toDouble(),
                              min: 1,
                              max: 500,
                              divisions: 499,
                              label: '${_effectiveCouponCount()}',
                              onChanged: _processing
                                  ? null
                                  : (v) {
                                      // step of 10 for readability, but keep min 1
                                      final rounded = (v / 10).round() * 10;
                                      setState(() => _couponCount = rounded.clamp(1, 500));
                                    },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Add-on: ${_money(couponsAddon)} ${pricing.currency}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RadioListTile<_CouponMode>(
                              value: _CouponMode.freeAccess,
                              groupValue: _couponMode,
                              onChanged: _processing
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      setState(() => _couponMode = v);
                                    },
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Free access (100%)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            RadioListTile<_CouponMode>(
                              value: _CouponMode.percentageDiscount,
                              groupValue: _couponMode,
                              onChanged: _processing
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      setState(() => _couponMode = v);
                                    },
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Percentage discount',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                'Slider: 5% – 90%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.65),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_couponMode == _CouponMode.percentageDiscount) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.percent, color: cs.onSurface.withOpacity(0.70), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Discount: ${_effectiveCouponPercent()}%',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.72),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _couponPercent.toDouble().clamp(5, 90),
                                min: 5,
                                max: 90,
                                divisions: 17, // step of 5
                                label: '${_effectiveCouponPercent()}%',
                                onChanged: _processing
                                    ? null
                                    : (v) {
                                        final rounded = (v / 5).round() * 5;
                                        setState(() => _couponPercent = rounded.clamp(5, 90));
                                      },
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Base: ${_money(baseFee)} ${pricing.currency}'
                      '  +  Viewers: ${_money(viewersAddon)} ${pricing.currency}'
                      '  +  Coupons: ${_buyCouponsForParticipants ? _money(couponsAddon) : _money(0)} ${pricing.currency}'
                      '  =  Total: ${_money(total)} ${pricing.currency}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
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
                                        viewerCapacity: _viewerCapacity,
                                        buyCouponsForParticipants: _buyCouponsForParticipants,
                                        couponDiscountPercent: _effectiveCouponPercent(),
                                        couponCount: _effectiveCouponCount(),
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
        ),
      ),
    );
  }
}
