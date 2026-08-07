// lib/features/leagues/logic/league_premium_upgrade_helper.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/payment_platform_config.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/widgets/glass.dart';
import '../../master_leagues/domain/master_league_plan.dart';
import '../../master_leagues/logic/master_leagues_providers.dart';

class LeaguePremiumUpgradeHelper {
  const LeaguePremiumUpgradeHelper._();

  static Future<bool> openUpgradeFlow(
    BuildContext context, {
    String leagueName = 'Organizer Premium',
  }) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              _InlinePlanPurchaseSheet(leagueName: leagueName),
        ) ??
        false;
  }
}

class _InlinePlanPurchaseSheet extends ConsumerStatefulWidget {
  const _InlinePlanPurchaseSheet({required this.leagueName});

  final String leagueName;

  @override
  ConsumerState<_InlinePlanPurchaseSheet> createState() =>
      _InlinePlanPurchaseSheetState();
}

class _InlinePlanPurchaseSheetState
    extends ConsumerState<_InlinePlanPurchaseSheet> {
  static const Color _premiumAmber = Color(0xFFF59E0B);

  MasterLeaguePlan _selectedPlan = MasterLeaguePlan.pro;
  PlanDuration _selectedDuration = PlanDuration.threeMonths;
  bool _processing = false;
  String? _error;

  bool get _useGooglePlay =>
      PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling;

  Color _panelFill(ThemeData theme) {
    if (theme.brightness == Brightness.light) {
      return Colors.white.withOpacity(0.58);
    }
    return theme.colorScheme.surface.withOpacity(0.78);
  }

  Color _panelBorder(ThemeData theme, {Color? accent}) {
    final cs = theme.colorScheme;
    final a = accent ?? cs.primary;
    if (theme.brightness == Brightness.light) {
      return Color.alphaBlend(
        a.withOpacity(0.16),
        Colors.white.withOpacity(0.82),
      );
    }
    return a.withOpacity(0.26);
  }

  List<BoxShadow>? _panelShadow(ThemeData theme, {Color? tint}) {
    if (theme.brightness != Brightness.light) return null;
    final c = tint ?? const Color(0xFFB4D2FF);
    return <BoxShadow>[
      BoxShadow(
        color: c.withOpacity(0.24),
        blurRadius: 34,
        offset: const Offset(0, 20),
      ),
    ];
  }

  String _planSubtitle(MasterLeaguePlan plan) {
    switch (plan) {
      case MasterLeaguePlan.basic:
        return 'Free starter access.';
      case MasterLeaguePlan.pro:
        return 'Create more leagues and unlock Pro organizer capacity.';
      case MasterLeaguePlan.elite:
        return 'Unlimited organizer scale with maximum competition capacity.';
    }
  }

  String _durationSubtitle(PlanDuration duration) {
    switch (duration) {
      case PlanDuration.threeMonths:
        return 'Good for testing premium access.';
      case PlanDuration.sixMonths:
        return 'Better value with extra savings.';
      case PlanDuration.yearly:
        return 'Best long-term value and highest savings.';
    }
  }

  // ── Payment Logic ─────────────────────────────────────────────────────────
  //
  // FIXED: Now correctly routes to GooglePlayBillingService when
  // _useGooglePlay is true, instead of blindly calling the Flutterwave
  // service (which was causing the "Unsupported provider" error).
  //
  // FIXED (2): the Google Play purchase's `purchaseToken` is now
  // captured and threaded through to activateAfterPayment(), which the
  // Cloudflare Worker needs to independently verify the purchase via
  // the Play Developer API before granting organizerPro custom claims.
  // Previously only `orderId` was captured, so this screen's purchases
  // would have hit the same "missing purchase token" wall the
  // create-workspace screen did before its fix.

  Future<void> _pay() async {
    if (_processing) return;

    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      setState(() {
        _error = 'Please sign in before purchasing a plan.';
      });
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);

      if (kDebugMode) {
        debugPrint(
          '[PlanPurchase] useGooglePlay=$_useGooglePlay '
          'plan=${_selectedPlan.id} duration=${_selectedDuration.id}',
        );
      }

      String receiptId = '';
      String provider = '';
      String purchaseToken = '';
      bool success = false;
      String? errorMessage;

      if (_useGooglePlay) {
        // ── Google Play Billing Path ────────────────────────────────
        final gpb = GooglePlayBillingService.instance;
        final attemptId =
            'gpb_${DateTime.now().millisecondsSinceEpoch}';

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
        // ── Flutterwave / Web Path ─────────────────────────────────
        final paymentSvc =
            ref.read(masterLeaguePaymentServiceProvider);

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

      // Activate the plan (Google Play -> worker verifies + sets
      // custom claims; Flutterwave -> worker verifies + sets custom
      // claims; both converge on the same authorization path).
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
        _error = e
            .toString()
            .replaceFirst('Exception: ', '')
            .trim();
      });
    }
  }

  Widget _sectionTitle(
    BuildContext context,
    String text,
    IconData icon, {
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = accent ?? cs.primary;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: a.withOpacity(0.14),
            border: Border.all(color: a.withOpacity(0.28)),
          ),
          child: Icon(icon, size: 18, color: a),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _planTile(
    BuildContext context, {
    required MasterLeaguePlan plan,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Color accent = plan == MasterLeaguePlan.elite
        ? _premiumAmber
        : cs.primary;

    final fill = selected
        ? accent.withOpacity(0.14)
        : (theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.42)
            : cs.onSurface.withOpacity(0.05));

    final border = selected
        ? accent.withOpacity(0.46)
        : (theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.74)
            : cs.onSurface.withOpacity(0.12));

    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fill,
          border: Border.all(
            color: border,
            width: selected ? 2 : 1,
          ),
          boxShadow: _panelShadow(theme, tint: accent),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? accent
                  : cs.onSurface.withOpacity(0.55),
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
                          style:
                              theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (plan.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E)
                                .withOpacity(0.12),
                            borderRadius:
                                BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF22C55E)
                                  .withOpacity(0.28),
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
                    _planSubtitle(plan),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.68),
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

  Widget _durationTile(
    BuildContext context, {
    required PlanDuration duration,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final fill = selected
        ? cs.primary.withOpacity(0.14)
        : (theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.42)
            : cs.onSurface.withOpacity(0.05));

    final border = selected
        ? cs.primary.withOpacity(0.46)
        : (theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.74)
            : cs.onSurface.withOpacity(0.12));

    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fill,
          border: Border.all(
            color: border,
            width: selected ? 2 : 1,
          ),
          boxShadow: _panelShadow(theme, tint: cs.primary),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? cs.primary
                  : cs.onSurface.withOpacity(0.55),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duration.displayName,
                    style:
                        theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _durationSubtitle(duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.68),
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (duration.discountLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF22C55E)
                        .withOpacity(0.26),
                  ),
                ),
                child: Text(
                  duration.discountLabel,
                  style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final benefits = _selectedPlan == MasterLeaguePlan.pro
        ? '• Create more than 3 leagues/competitions\n'
            '• Unlock Pro organizer access\n'
            '• Up to 5 master workspaces\n'
            '• More competition capacity'
        : '• Create more than 3 leagues/competitions\n'
            '• Unlock Elite organizer access\n'
            '• Unlimited workspaces\n'
            '• Unlimited competition capacity';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelFill(theme),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _panelBorder(
            theme,
            accent: _selectedPlan == MasterLeaguePlan.elite
                ? _premiumAmber
                : cs.primary,
          ),
        ),
        boxShadow: _panelShadow(
          theme,
          tint: _selectedPlan == MasterLeaguePlan.elite
              ? _premiumAmber
              : cs.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected summary',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Plan: ${_selectedPlan.displayName}\n'
            'Duration: ${_selectedDuration.displayName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.74),
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            benefits,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.72),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Google Play notice inside sheet
          if (_useGooglePlay) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: cs.primary.withOpacity(0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Purchase managed by Google Play Billing. '
                      'Manage subscriptions in the Play Store.',
                      style:
                          theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.74),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final Color accent = _selectedPlan == MasterLeaguePlan.elite
        ? _premiumAmber
        : cs.primary;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Glass(
            borderRadius: 30,
            padding: EdgeInsets.zero,
            child: Container(
              decoration: BoxDecoration(
                color: _panelFill(theme),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _panelBorder(theme, accent: accent),
                ),
                boxShadow: _panelShadow(theme, tint: accent),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              cs.onSurface.withOpacity(0.20),
                          borderRadius:
                              BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withOpacity(0.14),
                          border: Border.all(
                              color: accent.withOpacity(0.26)),
                        ),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          color: accent,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Choose a Plan',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.titleLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upgrade organizer access for '
                        '"${widget.leagueName}" '
                        'without leaving this screen.',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.74),
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(18),
                          border: Border.all(
                              color: accent.withOpacity(0.22)),
                        ),
                        child: Text(
                          'You reached your free limit. '
                          'Upgrade here to continue.',
                          textAlign: TextAlign.center,
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.80),
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment:
                            AlignmentDirectional.centerStart,
                        child: _sectionTitle(
                          context,
                          'Choose plan',
                          Icons.layers_rounded,
                          accent: accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _planTile(
                        context,
                        plan: MasterLeaguePlan.pro,
                        selected:
                            _selectedPlan == MasterLeaguePlan.pro,
                        onTap: () => setState(
                          () =>
                              _selectedPlan = MasterLeaguePlan.pro,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _planTile(
                        context,
                        plan: MasterLeaguePlan.elite,
                        selected: _selectedPlan ==
                            MasterLeaguePlan.elite,
                        onTap: () => setState(
                          () => _selectedPlan =
                              MasterLeaguePlan.elite,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment:
                            AlignmentDirectional.centerStart,
                        child: _sectionTitle(
                          context,
                          'Choose duration',
                          Icons.schedule_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _durationTile(
                        context,
                        duration: PlanDuration.threeMonths,
                        selected: _selectedDuration ==
                            PlanDuration.threeMonths,
                        onTap: () => setState(
                          () => _selectedDuration =
                              PlanDuration.threeMonths,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _durationTile(
                        context,
                        duration: PlanDuration.sixMonths,
                        selected: _selectedDuration ==
                            PlanDuration.sixMonths,
                        onTap: () => setState(
                          () => _selectedDuration =
                              PlanDuration.sixMonths,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _durationTile(
                        context,
                        duration: PlanDuration.yearly,
                        selected: _selectedDuration ==
                            PlanDuration.yearly,
                        onTap: () => setState(
                          () => _selectedDuration =
                              PlanDuration.yearly,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _summaryCard(context),
                      if ((_error ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.error.withOpacity(0.10),
                            borderRadius:
                                BorderRadius.circular(18),
                            border: Border.all(
                                color:
                                    cs.error.withOpacity(0.24)),
                          ),
                          child: Text(
                            _error!.trim(),
                            textAlign: TextAlign.center,
                            style:
                                theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _processing
                                  ? null
                                  : () => Navigator.of(context)
                                      .pop(false),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 14),
                                side: BorderSide(
                                  color: theme.brightness ==
                                          Brightness.light
                                      ? Colors.white
                                          .withOpacity(0.74)
                                      : cs.onSurface
                                          .withOpacity(0.18),
                                ),
                                foregroundColor:
                                    cs.onSurface.withOpacity(0.84),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  _processing ? null : _pay,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 14),
                                backgroundColor: accent,
                                foregroundColor: _selectedPlan ==
                                        MasterLeaguePlan.elite
                                    ? Colors.black
                                    : cs.onPrimary,
                              ),
                              child: _processing
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _selectedPlan ==
                                                MasterLeaguePlan
                                                    .elite
                                            ? Colors.black
                                            : cs.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      _useGooglePlay
                                          ? 'Buy on Play'
                                          : 'Pay Now',
                                      style: const TextStyle(
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
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
        ),
      ),
    );
  }
}