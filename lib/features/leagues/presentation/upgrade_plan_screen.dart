// lib/features/leagues/presentation/upgrade_plan_screen.dart
//
// UPDATED: _loadPriceForSelection() now branches on platform.
//
// For Google Play users (_useGooglePlay == true), the price shown is
// fetched LIVE from Play Console via GooglePlayBillingService
// .fetchPlanPrice() — i.e. queryProductDetails() under the hood. That
// is the exact price Google will charge, already formatted in the
// currency/amount tied to the user's Play Store account country
// (whatever you configured in Play Console: auto currency conversion
// or manual per-country pricing). No separate pricing service is
// consulted for these users anymore, so what's on screen always
// matches what gets charged at checkout.
//
// For non-Google-Play users (Flutterwave/web), pricing still comes
// from MasterLeaguePricingService as before — that path is unchanged.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/payment_platform_config.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../master_leagues/domain/master_league_plan.dart';
import '../../master_leagues/logic/master_league_pricing_service.dart';
import '../../master_leagues/logic/master_leagues_providers.dart';

class UpgradePlanScreen extends ConsumerStatefulWidget {
  const UpgradePlanScreen({super.key, this.initialPlan});

  /// Which tab to pre-select when the screen opens. Defaults to Pro
  /// (the "most popular" tier) if not specified.
  final MasterLeaguePlan? initialPlan;

  /// Pushes this screen and returns true if the user's plan changed
  /// (a purchase completed successfully), false otherwise (cancelled,
  /// back button, or failure). Matches the exact contract the old
  /// LeaguePremiumUpgradeHelper.openUpgradeFlow() already had, so
  /// callers don't need to change how they use the result.
  static Future<bool> open(
    BuildContext context, {
    MasterLeaguePlan? initialPlan,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UpgradePlanScreen(initialPlan: initialPlan),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<UpgradePlanScreen> createState() =>
      _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends ConsumerState<UpgradePlanScreen> {
  static const Color _premiumAmber = Color(0xFFF59E0B);

  late MasterLeaguePlan _selectedPlan;
  PlanDuration _selectedDuration = PlanDuration.threeMonths;

  bool _processing = false;
  bool _loadingPrice = false;
  String? _error;

  // priceCacheKey -> display string, e.g. "pro|3mo" -> "₦5,000".
  final Map<String, String> _priceCache = {};

  bool get _useGooglePlay =>
      PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.initialPlan ?? MasterLeaguePlan.pro;
    _loadPriceForSelection();
  }

  String _cacheKey(MasterLeaguePlan plan, PlanDuration duration) =>
      '${plan.id}|${duration.id}';

  // ── Price loading ─────────────────────────────────────────────────────────
  //
  // Google Play users: real, live price from Play Console.
  // Everyone else: MasterLeaguePricingService, unchanged.
  Future<void> _loadPriceForSelection() async {
    if (_selectedPlan.isFree) return;
    final key = _cacheKey(_selectedPlan, _selectedDuration);
    if (_priceCache.containsKey(key)) return;

    setState(() => _loadingPrice = true);

    try {
      if (_useGooglePlay) {
        final info = await GooglePlayBillingService.instance.fetchPlanPrice(
          plan: _selectedPlan,
          duration: _selectedDuration,
        );

        if (!mounted) return;

        if (info != null && info.formattedPrice.trim().isNotEmpty) {
          setState(() {
            _priceCache[key] = info.formattedPrice.trim();
            _loadingPrice = false;
          });
        } else {
          // Play Store had no price for this product right now (not
          // published yet, store unavailable, etc). Leave the cache
          // empty so the UI shows the '—' placeholder instead of a
          // wrong/mismatched number, and don't fall back to the other
          // pricing service — that would risk showing a price Google
          // Play won't actually honor at checkout.
          setState(() => _loadingPrice = false);
        }
        return;
      }

      final price = await MasterLeaguePricingService().getPlanPrice(
        plan: _selectedPlan,
        duration: _selectedDuration,
        locale: Localizations.maybeLocaleOf(context),
      );
      if (!mounted) return;
      if (price != null) {
        final symbol = price.currency.trim().toUpperCase() == 'NGN'
            ? '₦'
            : '\$';
        final amountStr = price.amount == price.amount.roundToDouble()
            ? price.amount.toStringAsFixed(0)
            : price.amount.toStringAsFixed(2);
        setState(() {
          _priceCache[key] = '$symbol$amountStr';
          _loadingPrice = false;
        });
      } else {
        setState(() => _loadingPrice = false);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UpgradePlanScreen] price load failed: $e');
      }
      if (!mounted) return;
      setState(() => _loadingPrice = false);
    }
  }

  String? get _currentPriceDisplay {
    if (_selectedPlan.isFree) return null;
    return _priceCache[_cacheKey(_selectedPlan, _selectedDuration)];
  }

  void _selectPlan(MasterLeaguePlan plan) {
    if (_selectedPlan == plan) return;
    setState(() {
      _selectedPlan = plan;
      _error = null;
    });
    _loadPriceForSelection();
  }

  void _selectDuration(PlanDuration duration) {
    if (_selectedDuration == duration) return;
    setState(() {
      _selectedDuration = duration;
      _error = null;
    });
    _loadPriceForSelection();
  }

  // ── Purchase flow ──────────────────────────────────────────────────────
  //
  // Same logic that used to live in league_premium_upgrade_helper.dart's
  // _InlinePlanPurchaseSheet._pay(): routes to Google Play Billing or
  // Flutterwave depending on platform config, then activates through
  // MasterLeagueEntitlementService.activateAfterPayment() -- which for
  // Google Play now verifies server-side via the Cloudflare Worker
  // before granting anything.
  Future<void> _pay() async {
    if (_processing || _selectedPlan.isFree) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      setState(() => _error = 'Please sign in before purchasing a plan.');
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);

      String receiptId = '';
      String provider = '';
      String purchaseToken = '';
      bool success = false;
      String? errorMessage;

      if (_useGooglePlay) {
        final gpb = GooglePlayBillingService.instance;
        final attemptId = 'gpb_${DateTime.now().millisecondsSinceEpoch}';

        final result = await gpb.purchasePlanSubscription(
          plan: _selectedPlan,
          duration: _selectedDuration,
          userId: uid,
          attemptId: attemptId,
        );

        success = result.success;
        errorMessage = result.errorMessage;
        receiptId = result.orderId;
        provider = result.provider;
        purchaseToken = result.purchaseToken;
      } else {
        final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);

        final result = await paymentSvc.payForPlanSubscription(
          context: context,
          userId: uid,
          plan: _selectedPlan,
          duration: _selectedDuration,
        );

        success = result.success;
        errorMessage = result.errorMessage;
        receiptId = result.receiptId ?? '';
        provider = result.provider;
        purchaseToken = result.txRef;
      }

      if (!mounted) return;

      if (!success) {
        setState(() {
          _processing = false;
          _error = errorMessage?.trim().isNotEmpty == true
              ? errorMessage
              : 'Payment failed.';
        });
        return;
      }

      await entitlementSvc.activateAfterPayment(
        plan: _selectedPlan,
        duration: _selectedDuration,
        receiptId: receiptId,
        provider: provider,
        purchaseToken: purchaseToken,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  // ── Feature lists ─────────────────────────────────────────────────────

  List<String> _featuresFor(MasterLeaguePlan plan) {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return const [
          '1 master league workspace',
          'Up to 3 competitions',
          'Standard organizer tools',
        ];
      case MasterLeaguePlan.pro:
        return const [
          '5 master league workspaces',
          'Up to 9 competitions per workspace',
          'Pro organizer badge',
          'Priority support',
        ];
      case MasterLeaguePlan.elite:
        return const [
          'Unlimited master league workspaces',
          'Unlimited competitions',
          'Elite organizer badge',
          'Maximum competition capacity',
          'Priority support',
        ];
    }
  }

  Color _accentFor(MasterLeaguePlan plan) {
    if (plan == MasterLeaguePlan.elite) return _premiumAmber;
    if (plan == MasterLeaguePlan.basic) return Colors.grey;
    return AppTheme.limeAccentDark;
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final accent = _accentFor(_selectedPlan);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Upgrade Your Plan'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: _processing
              ? null
              : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withOpacity(0.14),
                            border: Border.all(
                              color: accent.withOpacity(0.28),
                            ),
                          ),
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            color: accent,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Tier tabs ──────────────────────────────────
                        _PlanTabs(
                          selected: _selectedPlan,
                          onSelect: _selectPlan,
                        ),
                        const SizedBox(height: 20),

                        // ── Feature list ───────────────────────────────
                        Glass(
                          borderRadius: 22,
                          padding: const EdgeInsets.all(16),
                          fill: AppTheme.cardColor(brightness),
                          borderColor: AppTheme.cardBorder(brightness),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              for (final feature
                                  in _featuresFor(_selectedPlan))
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          vertical: 7),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          style: theme
                                              .textTheme.bodyMedium
                                              ?.copyWith(
                                            color:
                                                AppTheme.primaryText(
                                                    brightness),
                                            fontWeight:
                                                FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        if (_selectedPlan.isFree) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(16),
                              color: AppTheme.searchBackground(
                                  brightness),
                              border: Border.all(
                                color: AppTheme.searchOutline(
                                    brightness),
                              ),
                            ),
                            child: Text(
                              'Basic is your free starter plan and '
                              'requires no payment.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.secondaryText(
                                    brightness),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 20),
                          Align(
                            alignment:
                                AlignmentDirectional.centerStart,
                            child: Text(
                              'Choose duration',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryText(
                                    brightness),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _DurationSelector(
                            selected: _selectedDuration,
                            accent: accent,
                            onSelect: _selectDuration,
                          ),
                        ],

                        if ((_error ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error
                                  .withOpacity(0.10),
                              borderRadius:
                                  BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.error
                                    .withOpacity(0.24),
                              ),
                            ),
                            child: Text(
                              _error!.trim(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom price + CTA bar ──────────────────────────────────
            if (!_selectedPlan.isFree)
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  14 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(brightness),
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.cardBorder(brightness),
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _loadingPrice
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accent,
                                      ),
                                    )
                                  : Text(
                                      _currentPriceDisplay ?? '—',
                                      style: theme
                                          .textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.primaryText(
                                            brightness),
                                      ),
                                    ),
                              Text(
                                _selectedDuration.displayName,
                                style: TextStyle(
                                  color: AppTheme.secondaryText(
                                      brightness),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _processing ? null : _pay,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor:
                                _selectedPlan == MasterLeaguePlan.elite
                                    ? Colors.black
                                    : AppTheme.darkText,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(16),
                            ),
                          ),
                          child: _processing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _useGooglePlay
                                      ? 'Buy on Play'
                                      : 'Subscribe & Pay',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Tier tabs widget ─────────────────────────────────────────────────────

class _PlanTabs extends StatelessWidget {
  const _PlanTabs({required this.selected, required this.onSelect});

  final MasterLeaguePlan selected;
  final ValueChanged<MasterLeaguePlan> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    Widget tab(MasterLeaguePlan plan) {
      final isSelected = selected == plan;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(plan),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isSelected
                  ? AppTheme.limeAccent
                  : Colors.transparent,
            ),
            child: Column(
              children: [
                Text(
                  plan.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isSelected
                        ? AppTheme.darkText
                        : AppTheme.primaryText(brightness),
                  ),
                ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 2,
                    width: 24,
                    color: AppTheme.darkText,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.all(4),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          tab(MasterLeaguePlan.basic),
          tab(MasterLeaguePlan.pro),
          tab(MasterLeaguePlan.elite),
        ],
      ),
    );
  }
}

// ── Duration selector widget ─────────────────────────────────────────────

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  final PlanDuration selected;
  final Color accent;
  final ValueChanged<PlanDuration> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      children: PlanDuration.values.map((duration) {
        final isSelected = selected == duration;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onSelect(duration),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isSelected
                    ? accent.withOpacity(0.12)
                    : AppTheme.cardColor(brightness),
                border: Border.all(
                  color: isSelected
                      ? accent
                      : AppTheme.cardBorder(brightness),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected
                        ? accent
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
                  if (duration.hasDiscount)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        duration.discountLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}