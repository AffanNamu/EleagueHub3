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

  @override
  void dispose() {
    _masterLeagueNameCtrl.dispose();
    _competitionNameCtrl.dispose();
    super.dispose();
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

      final currentEnt = await entitlementSvc.getEntitlement(forceRefresh: true);
      final effectivePlan = currentEnt.plan ?? _selectedPlan;
      final currentWorkspaceCount = await entitlementSvc.countOwnedWorkspaces();

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
      if (kDebugMode) debugPrint('[CreateML][Web] Create failed: $e');
      _showMessage('$e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _planTile(
    MasterLeaguePlan plan,
    ThemeData theme,
    Brightness brightness,
  ) {
    final isSelected = _selectedPlan == plan;
    final isCurrent = _activePlan == plan;
    final lockedLowerPlan = !_canSelectPlan(plan);

    return Opacity(
      opacity: lockedLowerPlan ? 0.55 : 1.0,
      child: InkWell(
        onTap: (_processing || lockedLowerPlan)
            ? null
            : () => setState(() => _selectedPlan = plan),
        borderRadius: BorderRadius.circular(18),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(16),
          fill: isSelected
              ? (brightness == Brightness.dark
                  ? AppTheme.limeAccentDark.withOpacity(0.10)
                  : const Color(0xFFECFCCB))
              : AppTheme.cardColor(brightness),
          borderColor: isSelected
              ? AppTheme.limeAccentDark
              : AppTheme.cardBorder(brightness),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? AppTheme.limeAccentDark
                    : AppTheme.secondaryText(brightness),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          plan.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        if (plan.isPopular)
                          _chip(
                            'MOST POPULAR',
                            const Color(0xFF22C55E),
                          ),
                        if (isCurrent)
                          _chip(
                            'CURRENT',
                            AppTheme.limeAccentDark,
                          ),
                        if (plan.isFree)
                          _chip(
                            'FREE',
                            const Color(0xFF22C55E),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.45,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDurationSelector(ThemeData theme) {
    final brightness = theme.brightness;
    if (!_selectedNeedsPayment) return const SizedBox.shrink();

    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Duration',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 12),
          ...PlanDuration.values.map((dur) {
            final isSelected = _selectedDuration == dur;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _processing
                    ? null
                    : () => setState(() => _selectedDuration = dur),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isSelected
                        ? (brightness == Brightness.dark
                            ? AppTheme.limeAccentDark.withOpacity(0.10)
                            : const Color(0xFFECFCCB))
                        : AppTheme.searchBackground(brightness),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.limeAccentDark
                          : AppTheme.searchOutline(brightness),
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
                            ? AppTheme.limeAccentDark
                            : AppTheme.secondaryText(brightness),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dur.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                      ),
                      if (dur.hasDiscount)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dur.discountLabel,
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
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    Brightness brightness,
  ) {
    final planLabel = _selectedPlan.displayName;
    final durationLabel =
        _selectedNeedsPayment ? _selectedDuration.displayName : 'Free';
    final actionLabel = _shouldShowPaymentButton
        ? 'Choose Plan & Pay'
        : 'Create Workspace';

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creation Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow('Selected plan', planLabel, brightness),
          const SizedBox(height: 8),
          _summaryRow('Duration', durationLabel, brightness),
          const SizedBox(height: 8),
          _summaryRow(
            'Rewards',
            _enableRewards ? 'Enabled for first competition' : 'Disabled',
            brightness,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _processing
                  ? null
                  : (_shouldShowPaymentButton ? _openInlineUpgrade : _create),
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText,
                      ),
                    )
                  : Icon(
                      _shouldShowPaymentButton
                          ? Icons.payment_rounded
                          : Icons.add_circle_outline_rounded,
                    ),
              label: Text(
                _processing ? 'Processing...' : actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selectedPlan.isFree
                ? 'Basic plan is free. Your workspace will be created instantly.'
                : 'If your current limit is reached, choose another plan and pay without leaving this page.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (!_shouldShowPaymentButton) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _processing ? null : _create,
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text(
                'Create Now',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Brightness brightness) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 960;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Create Master League'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                Glass(
                  borderRadius: 30,
                  padding: const EdgeInsets.all(20),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create a new organizer workspace',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up your Master League, pick a plan, and create the first competition without leaving this screen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingEntitlement)
                        Text(
                          'Checking active plan...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else if (_activePlan != null)
                        Text(
                          'Active plan: ${_activePlan!.displayName} • Workspaces: $_ownedWorkspaceCount / ${_activePlan!.unlimitedMasterLeagues ? '∞' : '${_activePlan!.maxMasterLeagues}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.limeAccentDark,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else
                        Text(
                          'No active plan. Select a plan below.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (isCompact)
                  Column(
                    children: [
                      Glass(
                        borderRadius: 26,
                        padding: const EdgeInsets.all(18),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Workspace Details',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 14),
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
                              activeColor: AppTheme.limeAccentDark,
                              value: _enableRewards,
                              onChanged: _processing
                                  ? null
                                  : (v) => setState(() => _enableRewards = v),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Enable rewards for first competition',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryText(brightness),
                                ),
                              ),
                              subtitle: Text(
                                'Full reward details will be configured later.',
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Glass(
                        borderRadius: 26,
                        padding: const EdgeInsets.all(18),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose Plan',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...MasterLeaguePlan.values.map(
                              (plan) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _planTile(plan, theme, brightness),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDurationSelector(theme),
                      const SizedBox(height: 16),
                      _buildSummaryCard(theme, brightness),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            Glass(
                              borderRadius: 26,
                              padding: const EdgeInsets.all(18),
                              fill: AppTheme.cardColor(brightness),
                              borderColor: AppTheme.cardBorder(brightness),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Workspace Details',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.primaryText(brightness),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
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
                                    activeColor: AppTheme.limeAccentDark,
                                    value: _enableRewards,
                                    onChanged: _processing
                                        ? null
                                        : (v) => setState(() => _enableRewards = v),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Enable rewards for first competition',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.primaryText(brightness),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Full reward details will be configured later.',
                                      style: TextStyle(
                                        color: AppTheme.secondaryText(brightness),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Glass(
                              borderRadius: 26,
                              padding: const EdgeInsets.all(18),
                              fill: AppTheme.cardColor(brightness),
                              borderColor: AppTheme.cardBorder(brightness),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Choose Plan',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.primaryText(brightness),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ...MasterLeaguePlan.values.map(
                                    (plan) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _planTile(plan, theme, brightness),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            _buildDurationSelector(theme),
                            const SizedBox(height: 16),
                            _buildSummaryCard(theme, brightness),
                          ],
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
