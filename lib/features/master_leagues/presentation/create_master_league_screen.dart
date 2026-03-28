import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/master_leagues_repository_firebase.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import '../logic/master_league_pricing_service.dart';
import '../logic/master_leagues_providers.dart';

class CreateMasterLeagueScreen extends ConsumerStatefulWidget {
  const CreateMasterLeagueScreen({super.key});

  @override
  ConsumerState<CreateMasterLeagueScreen> createState() =>
      _CreateMasterLeagueScreenState();
}

class _CreateMasterLeagueScreenState
    extends ConsumerState<CreateMasterLeagueScreen> {
  final _masterLeagueNameCtrl = TextEditingController();
  final _competitionNameCtrl = TextEditingController();

  bool _processing = false;
  bool _loadingEntitlement = true;
  bool _enableRewards = false;

  MasterLeaguePlan _selectedPlan = MasterLeaguePlan.pro;
  MasterLeaguePlan? _activePlan;

  @override
  void initState() {
    super.initState();
    _loadEntitlement();
  }

  int _planOrder(MasterLeaguePlan? plan) {
    if (plan == null) return 0;
    if (plan == MasterLeaguePlan.basic) return 1;
    if (plan == MasterLeaguePlan.pro) return 2;
    if (plan == MasterLeaguePlan.elite) return 3;
    return 0;
  }

  bool _canSelectPlan(MasterLeaguePlan plan) {
    final active = _activePlan;
    if (active == null) return true;
    return _planOrder(plan) >= _planOrder(active);
  }

  Future<void> _loadEntitlement() async {
    try {
      final entitlementSvc = ref.read(masterLeagueEntitlementServiceProvider);
      final plan = await entitlementSvc.getActivePlan(forceRefresh: false);
      if (!mounted) return;

      setState(() {
        _activePlan = plan;
        _loadingEntitlement = false;
        if (plan != null && _planOrder(_selectedPlan) < _planOrder(plan)) {
          _selectedPlan = plan;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activePlan = null;
        _loadingEntitlement = false;
      });
    }
  }

  @override
  void dispose() {
    _masterLeagueNameCtrl.dispose();
    _competitionNameCtrl.dispose();
    super.dispose();
  }

  Future<MasterLeaguePrice?> _loadPriceForPlan(MasterLeaguePlan plan) async {
    try {
      final svc = MasterLeaguePricingService();
      return await svc.getMasterLeaguePriceForPlan(
        plan: plan,
        locale: Localizations.maybeLocaleOf(context),
      );
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        content: Text(text),
      ),
    );
  }

  MasterLeagueCompetitionDraft? _buildCompetitionDraft() {
    final competitionName = _competitionNameCtrl.text.trim();
    if (competitionName.isEmpty) {
      _showMessage('Please enter the competition name.', error: true);
      return null;
    }
    if (competitionName.length > 60) {
      _showMessage('Competition name is too long.', error: true);
      return null;
    }

    return MasterLeagueCompetitionDraft(
      name: competitionName,
      entryFee: 0,
      maxParticipants: 2,
      currency: _enableRewards ? 'REWARDS_ENABLED' : 'NONE',
    );
  }

  Future<bool> _showPaymentConfirmDialog({
    required MasterLeaguePrice? price,
    required bool preferNgn,
    required MasterLeaguePlan plan,
    required String masterLeagueName,
    required String competitionName,
    required bool rewardsEnabled,
  }) async {
    if (!mounted) return false;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String priceLine =
        price != null ? 'Workspace fee: ${price.display}' : 'Workspace fee unavailable';
    final String planLine = 'Plan: ${plan.displayName}';
    final String competitionLine =
        'First competition: $competitionName • Rewards: ${rewardsEnabled ? 'Enabled' : 'Disabled'}';

    final actualCurrency = (price?.currency ?? '').trim().toUpperCase();
    final String? warning =
        (preferNgn && actualCurrency.isNotEmpty && actualCurrency != 'NGN')
            ? 'NGN price is not configured. Falling back to $actualCurrency.'
            : null;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !_processing,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Glass(
            borderRadius: 28,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Proceed to Payment',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your organizer workspace will only be created after successful and verified payment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Master League: $masterLeagueName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  competitionLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(0.78),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$planLine\n$priceLine',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.error.withOpacity(0.30)),
                    ),
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text(
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
        );
      },
    );

    return result == true;
  }

  Future<void> _create() async {
    if (_processing) return;

    final masterLeagueName = _masterLeagueNameCtrl.text.trim();
    if (masterLeagueName.isEmpty) {
      _showMessage('Please enter a Master League name.', error: true);
      return;
    }
    if (masterLeagueName.length > 60) {
      _showMessage('Master League name is too long.', error: true);
      return;
    }

    final competition = _buildCompetitionDraft();
    if (competition == null) return;

    setState(() => _processing = true);

    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final entitlementSvc = ref.read(masterLeagueEntitlementServiceProvider);
      final effectivePlan = _activePlan ?? _selectedPlan;

      await repo.checkMasterLeagueLimitOrThrow(effectivePlan);

      final price = await _loadPriceForPlan(effectivePlan);
      final cc = await CountryResolverService.instance.resolveCountryCode(
        locale: Localizations.maybeLocaleOf(context),
      );
      final preferNgn = cc.trim().toUpperCase() == 'NG';

      final shouldProceed = await _showPaymentConfirmDialog(
        price: price,
        preferNgn: preferNgn,
        plan: effectivePlan,
        masterLeagueName: masterLeagueName,
        competitionName: competition.name,
        rewardsEnabled: _enableRewards,
      );

      if (!shouldProceed) {
        if (mounted) setState(() => _processing = false);
        return;
      }

      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      final payment = await paymentSvc.payForMasterLeagueCreation(
        context: context,
        userId: userId,
        plan: effectivePlan,
        masterLeagueName: masterLeagueName,
        competition: competition,
      );

      if (!mounted) return;

      if (!payment.success) {
        _showMessage(
          payment.errorMessage ?? 'Payment failed. Please try again.',
          error: true,
        );
        return;
      }

      // ============================================================
      // FIX: Activate Organizer Pro BEFORE creating Master League.
      //
      // This calls the /organizer-pro/activate endpoint which:
      //   1. Verifies the Flutterwave transaction (server-side)
      //   2. Sets Firebase custom claims (organizerPro=true, plan, expiry)
      //   3. Creates the entitlement document in Firestore
      //
      // Without this step, the Firestore security rules block the
      // Master League creation because the user doesn't have the
      // organizerPro claim yet.
      // ============================================================
      try {
        if (kDebugMode) {
          debugPrint('[CreateML] Activating Organizer Pro for plan: ${effectivePlan.id}...');
        }

        await entitlementSvc.activateAfterPayment(
          plan: effectivePlan,
          payment: payment,
        );

        if (kDebugMode) {
          debugPrint('[CreateML] Organizer Pro activated successfully.');
        }

        // Force refresh the Firebase ID token so the new custom claims
        // are included in subsequent Firestore requests.
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
      } catch (activationError) {
        if (kDebugMode) {
          debugPrint('[CreateML] Organizer Pro activation failed: $activationError');
          debugPrint('[CreateML] Proceeding with Master League creation anyway...');
        }
        // Don't block Master League creation if activation fails.
        // The payment is verified and the master league doc will be
        // created with the payment proof. The user can retry activation later.
        //
        // Still try to force-refresh the token in case claims were partially set.
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      }

      // Now create the Master League with the verified payment proof.
      final created = await repo.createAfterVerifiedPayment(
        masterLeagueName: masterLeagueName,
        plan: effectivePlan,
        attemptId: payment.attemptId,
        paymentId: payment.paymentId,
        receiptId: payment.receiptId ?? '',
        competition: competition,
      );

      if (!mounted) return;

      _showMessage('Master League created successfully.');
      context.go('/master-leagues/${created.id}');
    } on UserFriendlyException catch (e) {
      _showMessage(e.message, error: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CreateML] Create failed: $e');
      }
      _showMessage('$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Widget _buildPlanTile(
    BuildContext context,
    MasterLeaguePlan plan,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isSelected = _selectedPlan == plan;
    final isCurrent = _activePlan == plan;
    final lockedLowerPlan = !_canSelectPlan(plan);

    final Color borderColor;
    final Color bgColor;

    if (isSelected) {
      borderColor = cs.primary;
      bgColor = cs.primary.withOpacity(0.08);
    } else {
      borderColor = cs.onSurface.withOpacity(0.12);
      bgColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: lockedLowerPlan ? 0.55 : 1.0,
        child: InkWell(
          onTap: (_processing || lockedLowerPlan)
              ? null
              : () => setState(() => _selectedPlan = plan),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: bgColor,
              border: Border.all(
                color: borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.35),
                      width: 2,
                    ),
                    color: isSelected ? cs.primary : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            plan.displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          if (plan.isPopular)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      const Color(0xFF22C55E).withOpacity(0.30),
                                ),
                              ),
                              child: const Text(
                                'MOST POPULAR',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF22C55E),
                                ),
                              ),
                            ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: cs.primary.withOpacity(0.28),
                                ),
                              ),
                              child: Text(
                                'CURRENT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteCard(ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use this screen to create your organizer workspace and first competition. If rewards are enabled, you will complete the full reward setup later inside the competition using your built-in rewards system.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.72),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Create Master League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
              children: [
                Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withOpacity(0.12),
                              border: Border.all(
                                color: cs.primary.withOpacity(0.25),
                              ),
                            ),
                            child: Icon(
                              Icons.hub_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Create New Master League',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter a workspace name and first competition name. Rewards can be enabled here and fully configured later inside your competition reward system.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingEntitlement)
                        Text(
                          'Checking active plan...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else if (_activePlan != null)
                        Text(
                          'Active plan: ${_activePlan!.displayName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else
                        Text(
                          'No active Organizer Pro claim found. You can still continue to payment for your selected plan.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _masterLeagueNameCtrl,
                        enabled: !_processing,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Master League Name',
                          prefixIcon: Icon(Icons.edit_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _competitionNameCtrl,
                        enabled: !_processing,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _create(),
                        decoration: const InputDecoration(
                          labelText: 'Competition Name',
                          prefixIcon: Icon(Icons.emoji_events_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        value: _enableRewards,
                        onChanged: _processing
                            ? null
                            : (v) => setState(() => _enableRewards = v),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable rewards for first competition',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text(
                          'Full reward details will be configured later inside the competition.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _noteCard(theme, cs),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'Choose Plan',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                ...MasterLeaguePlan.values.map(
                  (plan) => _buildPlanTile(context, plan, theme, cs),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _processing ? null : _create,
                  icon: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment_rounded),
                  label: Text(
                    _processing ? 'Processing...' : 'Proceed to Payment',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Your Master League is created only after workspace payment succeeds and is verified.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.60),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
