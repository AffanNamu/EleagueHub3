import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../data/leagues_repository_local.dart';
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
  bool _processingPayment = false;

  League? _league;
  String _userId = '';
  bool _hasPaid = false;
  LeagueChargesReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  Future<void> _load() async {
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

    if (!mounted) return;
    setState(() {
      _league = league;
      _userId = userId;
      _hasPaid = hasPaid;
      _receipt = receipt;
      _loading = false;
    });
  }

  bool _isClassicFree(League league) => league.format == LeagueFormat.classic;

  bool _isOrganizerAlwaysAllowed(League league) => league.organizerUserId == _userId;

  bool _requiresCharges(League league) =>
      league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    final league = _league;
    if (league == null) {
      return Center(
        child: Glass(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.tr('leagues_error_not_found_local_storage'),
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isClassicFree(league)) return widget.child;

    if (_isOrganizerAlwaysAllowed(league)) return widget.child;

    if (!_requiresCharges(league)) return widget.child;

    if (_hasPaid) return widget.child;

    final pricing = FlutterwaveConfig.pricingForLocale(Localizations.maybeLocaleOf(context));

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
                  color: Colors.cyanAccent.withOpacity(0.95),
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('league_access_charges_required_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${l10n.tr('league_access_amount_prefix')} ${pricing.viewLeagueAmount} ${pricing.currency}\n\n'
                  '${l10n.tr('league_access_charges_explanation')}\n\n'
                  '${l10n.tr('league_access_league_prefix')} ${league.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    height: 1.35,
                  ),
                ),
                if (_receipt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.tr('league_access_receipt_prefix')} ${_receipt!.receiptId}',
                    style: TextStyle(color: Colors.white.withOpacity(0.80)),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _processingPayment ? null : () => _pay(context, league),
                        child: _processingPayment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.tr('league_access_pay_charges')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tr('league_access_note_classic_free'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, League league) async {
    final l10n = context.l10n;

    setState(() => _processingPayment = true);

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
          SnackBar(content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed'))),
        );
        setState(() => _processingPayment = false);
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
        _processingPayment = false;
        _hasPaid = true;
        _receipt = receipt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_access_charges_paid_success'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.tr('league_access_payment_failed_prefix')} $e')),
      );
    }
  }
}
