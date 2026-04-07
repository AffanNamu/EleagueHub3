import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/master_leagues/domain/master_league.dart';
import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../../features/master_leagues/logic/master_leagues_providers.dart';

class WebCreateMasterLeagueScreen extends ConsumerStatefulWidget {
  const WebCreateMasterLeagueScreen({super.key});

  @override
  ConsumerState<WebCreateMasterLeagueScreen> createState() =>
      _WebCreateMasterLeagueScreenState();
}

class _WebCreateMasterLeagueScreenState
    extends ConsumerState<WebCreateMasterLeagueScreen> {
  final _masterLeagueNameCtrl = TextEditingController();
  final _competitionNameCtrl = TextEditingController();

  bool _processing = false;
  bool _loadingEntitlement = true;
  bool _enableRewards = false;

  MasterLeaguePlan _selectedPlan = MasterLeaguePlan.basic;
  PlanDuration _selectedDuration = PlanDuration.threeMonths;
  MasterLeaguePlan? _activePlan;
  int _ownedWorkspaceCount = 0;

  String _lastVerifiedAttemptId = '';
  String _lastVerifiedPaymentId = '';
  String _lastVerifiedReceiptId = '';

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
      final ent = await entitlementSvc.getEntitlement(forceRefresh: false);
      final count = await entitlementSvc.countOwnedWorkspaces();
      if (!mounted) return;

      setState(() {
        _activePlan = ent.plan;
        _ownedWorkspaceCount = count;
        _loadingEntitlement = false;
        if (ent.plan != null &&
            _planOrder(_selectedPlan) < _planOrder(ent.plan!)) {
          _selectedPlan = ent.plan!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activePlan = null;
        _ownedWorkspaceCount = 0;
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

  bool get _selectedNeedsPayment => _selectedPlan.requiresPayment;

  bool get _shouldShowPaymentButton {
    if (_selectedPlan.isFree) return false;
    if (_activePlan != null &&
        _planOrder(_activePlan!) >= _planOrder(_selectedPlan) &&
        _activePlan!.canCreateWorkspace(_ownedWorkspaceCount)) {
      return false;
    }
    return true;
  }

  Future<bool> _openInlineUpgrade() async {
    final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
    final entitlementSvc = ref.read(masterLeagueEntitlementServiceProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    if (uid.isEmpty) {
      _showMessage('Please sign in and try again.', error: true);
      return false;
    }

    final result = await paymentSvc.payForPlanSubscription(
      context: context,
      userId: uid,
      plan: _selectedPlan,
      duration: _selectedDuration,
    );

    if (!mounted) return false;

    if (!result.success) {
      _showMessage(
        result.errorMessage ?? 'Payment failed. Please try again.',
        error: true,
      );
      return false;
    }

    await entitlementSvc.activateAfterPayment(
      plan: _selectedPlan,
      duration: _selectedDuration,
      receiptId: result.receiptId ?? '',
      provider: result.provider,
    );

    _lastVerifiedAttemptId = result.attemptId;
    _lastVerifiedPaymentId = result.paymentId;
    _lastVerifiedReceiptId = result.receiptId ?? '';

    await _loadEntitlement();
    return true;
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

      final currentEnt =
          await entitlementSvc.getEntitlement(forceRefresh: true);
      final effectivePlan = currentEnt.plan ?? _selectedPlan;
      final currentWorkspaceCount =
          await entitlementSvc.countOwnedWorkspaces();

      if (!effectivePlan.canCreateWorkspace(currentWorkspaceCount)) {
        _showMessage(
          'You have reached the workspace limit for ${effectivePlan.displayName} plan.',
          error: true,
        );
        if (mounted) setState(() => _processing = false);
        return;
      }

      if (_selectedPlan.isFree) {
        if (currentEnt.plan == null) {
          await entitlementSvc.activateBasicFreePlan();
        }

        final created = await repo.create(
          name: masterLeagueName,
          plan: MasterLeaguePlan.basic,
          initialCompetition: competition,
        );

        if (!mounted) return;
        _showMessage('Basic Master League created successfully.');
        context.go('/master-leagues/${created.id}');
        return;
      }

      if (_shouldShowPaymentButton) {
        final upgraded = await _openInlineUpgrade();
        if (!mounted) return;

        if (!upgraded) {
          setState(() => _processing = false);
          return;
        }
      }

      final refreshedEnt =
          await entitlementSvc.getEntitlement(forceRefresh: true);
      final refreshedPlan = refreshedEnt.plan ?? _selectedPlan;

      if (_lastVerifiedAttemptId.trim().isEmpty ||
          _lastVerifiedPaymentId.trim().isEmpty ||
          _lastVerifiedReceiptId.trim().isEmpty) {
        _showMessage(
          'Verified payment details are missing. Please try again.',
          error: true,
        );
        setState(() => _processing = false);
        return;
      }

      final created = await repo.createAfterVerifiedPayment(
        masterLeagueName: masterLeagueName,
        plan: refreshedPlan,
        attemptId: _lastVerifiedAttemptId,
        paymentId: _lastVerifiedPaymentId,
        receiptId: _lastVerifiedReceiptId,
        competition: competition,
      );

      if (!mounted) return;
      _showMessage('Master League created successfully.');
      context.go('/master-leagues/${created.id}');
    } catch (e) {
      if (kDebugMode) debugPrint('[CreateML] Create failed: $e');
      _showMessage('$e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return GlassScaffold(
      useBubbles: false,
      appBar: AppBar(
        title: const Text('Create Organizer Workspace'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1000 : 600),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            flex: 5, child: _buildForm(brightness)),
                        const SizedBox(width: 32),
                        Expanded(
                            flex: 4,
                            child: _buildPlanSelection(brightness)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildForm(brightness),
                        const SizedBox(height: 32),
                        _buildPlanSelection(brightness),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(Brightness brightness) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(32),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.limeAccent.withOpacity(0.15),
                ),
                child: const Icon(Icons.hub_rounded,
                    color: AppTheme.limeAccentDark, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workspace Details',
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set up your master brand and initial competition.',
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _MasterWebTextField(
            controller: _masterLeagueNameCtrl,
            label: 'Workspace Name (Brand / Organizer)',
            icon: Icons.business_center_outlined,
            brightness: brightness,
            enabled: !_processing,
          ),
          const SizedBox(height: 20),
          _MasterWebTextField(
            controller: _competitionNameCtrl,
            label: 'First Competition Name',
            icon: Icons.emoji_events_outlined,
            brightness: brightness,
            enabled: !_processing,
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.searchBackground(brightness),
              border:
                  Border.all(color: AppTheme.searchOutline(brightness)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable Rewards',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure prize pools after creation.',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _enableRewards,
                  onChanged: _processing
                      ? null
                      : (v) => setState(() => _enableRewards = v),
                  activeColor: AppTheme.limeAccentDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSelection(Brightness brightness) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadingEntitlement)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.searchBackground(brightness),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.limeAccentDark)),
          )
        else if (_activePlan != null)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: AppTheme.limeAccentDark.withOpacity(0.1),
              border: Border.all(
                  color: AppTheme.limeAccentDark.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded,
                    color: AppTheme.limeAccentDark, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Plan: ${_activePlan!.displayName}',
                        style: TextStyle(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w900,
                            fontSize: 16),
                      ),
                      Text(
                        'Workspaces Used: $_ownedWorkspaceCount / ${_activePlan!.unlimitedMasterLeagues ? '∞' : '${_activePlan!.maxMasterLeagues}'}',
                        style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Select a Plan',
          style: TextStyle(
            color: AppTheme.primaryText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 16),
        ...MasterLeaguePlan.values.map((plan) {
          final isSelected = _selectedPlan == plan;
          final isCurrent = _activePlan == plan;
          final locked = !_canSelectPlan(plan);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Opacity(
              opacity: locked ? 0.5 : 1.0,
              child: InkWell(
                onTap: (_processing || locked)
                    ? null
                    : () => setState(() => _selectedPlan = plan),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.limeAccentDark.withOpacity(0.08)
                        : AppTheme.cardColor(brightness),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.limeAccentDark
                          : AppTheme.cardBorder(brightness),
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected
                            ? AppTheme.limeAccentDark
                            : AppTheme.secondaryText(brightness),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  plan.displayName,
                                  style: TextStyle(
                                      color:
                                          AppTheme.primaryText(brightness),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                if (plan.isPopular)
                                  _badge('POPULAR',
                                      const Color(0xFF22C55E)),
                                if (isCurrent)
                                  _badge('CURRENT',
                                      AppTheme.limeAccentDark),
                                if (plan.isFree)
                                  _badge(
                                      'FREE', const Color(0xFF38BDF8)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plan.description,
                              style: TextStyle(
                                  color:
                                      AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  height: 1.3),
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
        }),
        if (_selectedNeedsPayment) ...[
          const SizedBox(height: 16),
          Text(
            'Billing Cycle',
            style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w900,
                fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: PlanDuration.values.map((dur) {
              final isSelected = _selectedDuration == dur;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: _processing
                        ? null
                        : () =>
                            setState(() => _selectedDuration = dur),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.limeAccentDark.withOpacity(0.08)
                            : AppTheme.cardColor(brightness),
                        border: Border.all(
                            color: isSelected
                                ? AppTheme.limeAccentDark
                                : AppTheme.cardBorder(brightness)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            dur.displayName,
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryText(brightness)
                                  : AppTheme.secondaryText(brightness),
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                          if (dur.hasDiscount)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                dur.discountLabel,
                                style: const TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.limeAccent,
            foregroundColor: AppTheme.darkText,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _processing
              ? null
              : (_shouldShowPaymentButton ? _openInlineUpgrade : _create),
          child: _processing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: AppTheme.darkText))
              : Text(
                  _shouldShowPaymentButton
                      ? 'PROCEED TO PAYMENT'
                      : 'CREATE WORKSPACE',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5)),
    );
  }
}

class _MasterWebTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Brightness brightness;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  const _MasterWebTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.brightness,
    required this.enabled,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onSubmitted: onSubmitted,
      style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.secondaryText(brightness)),
        filled: true,
        fillColor: AppTheme.searchBackground(brightness),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: AppTheme.limeAccentDark, width: 2),
        ),
      ),
    );
  }
}
