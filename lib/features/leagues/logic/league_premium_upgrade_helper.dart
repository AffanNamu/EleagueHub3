import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../../master_leagues/logic/master_league_entitlement_service.dart';
import '../../master_leagues/logic/master_league_payment_service.dart';
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
          backgroundColor: Colors.transparent,
          builder: (_) => _InlinePlanPurchaseSheet(leagueName: leagueName),
        ) ??
        false;
  }
}

class _InlinePlanPurchaseSheet extends ConsumerStatefulWidget {
  const _InlinePlanPurchaseSheet({
    required this.leagueName,
  });

  final String leagueName;

  @override
  ConsumerState<_InlinePlanPurchaseSheet> createState() =>
      _InlinePlanPurchaseSheetState();
}

class _InlinePlanPurchaseSheetState
    extends ConsumerState<_InlinePlanPurchaseSheet> {
  MasterLeaguePlan _selectedPlan = MasterLeaguePlan.pro;
  PlanDuration _selectedDuration = PlanDuration.threeMonths;
  bool _processing = false;
  String? _error;

  Future<void> _pay() async {
    if (_processing) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final entitlementSvc = ref.read(masterLeagueEntitlementServiceProvider);

      final uid = '';
      final result = await paymentSvc.payForPlanSubscription(
        context: context,
        userId: uid,
        plan: _selectedPlan,
        duration: _selectedDuration,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _processing = false;
          _error = result.errorMessage ?? 'Payment failed.';
        });
        return;
      }

      await entitlementSvc.activateAfterPayment(
        plan: _selectedPlan,
        duration: _selectedDuration,
        receiptId: result.receiptId ?? '',
        provider: result.provider,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = e.toString();
      });
    }
  }

  Widget _planTile(
    BuildContext context, {
    required MasterLeaguePlan plan,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? cs.primary.withOpacity(0.10) : cs.surface,
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.30),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? cs.primary : cs.onSurface.withOpacity(0.60),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plan.displayName,
                style: const TextStyle(fontWeight: FontWeight.w900),
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _processing ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? cs.primary.withOpacity(0.10) : cs.surface,
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withOpacity(0.30),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                duration.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (duration.discountLabel.isNotEmpty)
              Text(
                duration.discountLabel,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Choose a Plan',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'You reached your free limit. Upgrade here without leaving this screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.70),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _planTile(
                  context,
                  plan: MasterLeaguePlan.pro,
                  selected: _selectedPlan == MasterLeaguePlan.pro,
                  onTap: () => setState(() => _selectedPlan = MasterLeaguePlan.pro),
                ),
                const SizedBox(height: 10),
                _planTile(
                  context,
                  plan: MasterLeaguePlan.elite,
                  selected: _selectedPlan == MasterLeaguePlan.elite,
                  onTap: () => setState(() => _selectedPlan = MasterLeaguePlan.elite),
                ),
                const SizedBox(height: 16),
                _durationTile(
                  context,
                  duration: PlanDuration.threeMonths,
                  selected: _selectedDuration == PlanDuration.threeMonths,
                  onTap: () =>
                      setState(() => _selectedDuration = PlanDuration.threeMonths),
                ),
                const SizedBox(height: 8),
                _durationTile(
                  context,
                  duration: PlanDuration.sixMonths,
                  selected: _selectedDuration == PlanDuration.sixMonths,
                  onTap: () =>
                      setState(() => _selectedDuration = PlanDuration.sixMonths),
                ),
                const SizedBox(height: 8),
                _durationTile(
                  context,
                  duration: PlanDuration.yearly,
                  selected: _selectedDuration == PlanDuration.yearly,
                  onTap: () =>
                      setState(() => _selectedDuration = PlanDuration.yearly),
                ),
                if ((_error ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _processing ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _processing ? null : _pay,
                        child: _processing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Pay Now',
                                style: TextStyle(fontWeight: FontWeight.w900),
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
  }
}
