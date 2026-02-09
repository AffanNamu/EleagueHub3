import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../data/leagues_repository_local.dart';
import '../logic/coupon_config_service.dart';
import '../logic/coupon_redemption_service.dart';
import '../logic/league_charges_payment_service.dart';
import '../logic/league_charges_store.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../utils/current_user.dart';

class LeagueAccessGuard extends ConsumerStatefulWidget {
  const LeagueAccessGuard({
    super.key,
    required this.leagueId,
    required this.child,
  });

  final String leagueId;
  final Widget child;

  @override
  ConsumerState<LeagueAccessGuard> createState() => _LeagueAccessGuardState();
}

class _LeagueAccessGuardState extends ConsumerState<LeagueAccessGuard> {
  bool _loading = true;
  bool _processing = false;

  League? _league;
  String _userId = '';
  bool _hasPaid = false;
  LeagueChargesReceipt? _receipt;

  // Determines classic free participant access vs viewer payment gate.
  bool _isParticipant = false;

  RemotePricingPlan? _plan;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    final league = await repo.getLeagueById(widget.leagueId);

    String userId = prefs.getCurrentUserId() ?? '';
    if (userId.trim().isEmpty) {
      userId = await CurrentUser.getOrCreateUserId();
    }

    final store = LeagueChargesStore(prefs);

    final hasPaid = store.hasPaidCharges(userId: userId, leagueId: widget.leagueId);
    final receipt = store.getReceipt(userId: userId, leagueId: widget.leagueId);

    bool isParticipant = false;
    try {
      final membership = await repo.getMembership(
        leagueId: widget.leagueId,
        userId: userId,
      );
      isParticipant = membership != null;
    } catch (_) {
      isParticipant = false;
    }

    final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));

    if (!mounted) return;
    setState(() {
      _league = league;
      _userId = userId;
      _hasPaid = hasPaid;
      _receipt = receipt;
      _isParticipant = isParticipant;
      _plan = plan;
      _loading = false;
    });
  }

  bool _isClassic(League league) => league.format == LeagueFormat.classic;

  bool _isOrganizerAlwaysAllowed(League league) => league.organizerUserId == _userId;

  // New gating rules:
  // - Classic: participants free; non-participants must pay.
  // - UCL Group / Swiss: all non-organizers must pay (participants and viewers).
  bool _requiresPaymentGateForUser(League league) {
    if (_isOrganizerAlwaysAllowed(league)) return false;

    if (_isClassic(league)) {
      return !_isParticipant; // participants free; others pay
    }

    // Paid formats: gate everyone except organizer.
    return true;
  }

  String _money(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  Future<void> _payStandardAccess(League league) async {
    final l10n = context.l10n;
    setState(() => _processing = true);

    try {
      final prefs = ref.read(prefsServiceProvider);
      final payment = ref.read(leagueChargesPaymentServiceProvider);
      final store = LeagueChargesStore(prefs);

      final result = await payment.payLeagueCharges(
        context: context,
        userId: _userId,
        leagueId: league.id,
        leagueName: league.name,
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _processing = false);
        return;
      }

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: _userId,
        receiptId: result.receiptId ?? '',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;
      setState(() {
        _processing = false;
        _hasPaid = true;
        _receipt = receipt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_access_charges_paid_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_access_payment_failed_prefix')} $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _redeemOrganizerCoupon(League league) async {
    final l10n = context.l10n;
    setState(() => _processing = true);

    try {
      final prefs = ref.read(prefsServiceProvider);
      final store = LeagueChargesStore(prefs);

      final svc = CouponRedemptionService();
      final result = await svc.redeemNow(
        context: context,
        league: league,
        userId: _userId,
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Redemption failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _processing = false);
        return;
      }

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: _userId,
        receiptId: result.receiptId ?? 'CPN',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;
      setState(() {
        _processing = false;
        _hasPaid = true;
        _receipt = receipt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_access_charges_paid_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Redemption failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    final league = _league;
    if (league == null) {
      return Center(
        child: Glass(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.tr('leagues_error_not_found_local_storage'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // If no gate required for this user, allow.
    if (!_requiresPaymentGateForUser(league)) return widget.child;

    // If already paid, allow.
    if (_hasPaid) return widget.child;

    if (_plan == null) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    final plan = _plan!;
    final baseAmount = plan.accessFee;

    final gateReasonText = _isClassic(league)
        ? 'This Classic league is free for participants only (max 20). Non-participants must pay to view.'
        : l10n.tr('league_access_charges_explanation');

    // Load coupon config to determine if organizer-subsidized redemption is available.
    return FutureBuilder<CouponConfig?>(
      future: CouponConfigService().getConfig(league.id),
      builder: (context, snap) {
        final hasCfg = snap.hasData && snap.data != null;
        final cfg = snap.data;

        // Compute redemption price if config exists.
        final double redeemPay = hasCfg
            ? double.parse((cfg!.effectiveUnit * (cfg.userPaysPercent / 100.0)).toStringAsFixed(2))
            : 0.0;
        final String redeemCurrency = hasCfg ? cfg!.currency : plan.currency;

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Glass(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: cs.primary.withOpacity(0.95),
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.tr('league_access_charges_required_title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${l10n.tr('league_access_amount_prefix')} ${_money(baseAmount)} ${plan.currency}\n\n'
                      '$gateReasonText\n\n'
                      '${l10n.tr('league_access_league_prefix')} ${league.name}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_receipt != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${l10n.tr('league_access_receipt_prefix')} ${_receipt!.receiptId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.80),
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Primary action: if organizer configured coupons, allow redemption.
                    if (hasCfg) ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _processing ? null : () => _redeemOrganizerCoupon(league),
                              icon: const Icon(Icons.confirmation_number_outlined),
                              label: Text(
                                redeemPay <= 0
                                    ? 'Redeem organizer coupon (Free)'
                                    : 'Redeem organizer coupon • ${_money(redeemPay)} $redeemCurrency',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your organizer enabled coupons for this league. Redeem once to unlock viewing.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.60),
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: cs.onSurface.withOpacity(0.10)),
                    ],

                    // Fallback: standard access fee (when no coupon config).
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _processing ? null : () => _payStandardAccess(league),
                            child: _processing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    hasCfg
                                        ? 'Or pay ${_money(baseAmount)} ${plan.currency}'
                                        : l10n.tr('league_access_pay_charges'),
                                  ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Text(
                      l10n.tr('league_access_note_classic_free'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.55),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
