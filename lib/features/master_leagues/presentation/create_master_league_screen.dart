// lib/features/master_leagues/presentation/create_master_league_screen.dart
//
// UPDATED: all inline plan purchasing has been removed from this screen.
// Payment now happens EXCLUSIVELY inside UpgradePlanScreen
// (lib/features/leagues/presentation/upgrade_plan_screen.dart). This
// screen no longer talks to GooglePlayBillingService or the Flutterwave
// payment service directly, no longer has plan tiles or a duration
// selector, and no longer builds createAfterVerifiedPayment() receipt
// args. Instead:
//   1. It tries to create the workspace against whatever plan is
//      currently verified server-side (defaulting to an implicit free
//      Basic plan the very first time).
//   2. If that plan is out of workspace capacity, it pushes
//      UpgradePlanScreen and waits for a bool result.
//   3. On success it re-reads the server-verified plan (with retry, to
//      absorb activation propagation delay) and creates the workspace.
// An explicit "Upgrade Plan" button also sits at the top of the action
// panel so users can jump to UpgradePlanScreen proactively, without
// first hitting the capacity limit.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/presentation/upgrade_plan_screen.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import '../logic/master_leagues_providers.dart';

// ── Breakpoints ───────────────────────────────────────────────────────────────

class _BP {
  static const double tablet = 760;
  static const double desktop = 900;
  static const double wide = 1200;
}

// ── Screen ────────────────────────────────────────────────────────────────────

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

  MasterLeaguePlan? _activePlan;
  int _ownedWorkspaceCount = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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

  // ── Safe navigation ───────────────────────────────────────────────────────

  void _safeGo(String location) {
    try {
      GoRouter.of(context).go(location);
    } catch (e) {
      debugPrint('[CreateMasterLeague] go($location) failed: $e');
    }
  }

  void _safePop() {
    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  // ── Plan helpers ──────────────────────────────────────────────────────────

  MasterLeaguePlan _nextPlanAbove(MasterLeaguePlan plan) {
    if (plan == MasterLeaguePlan.basic) return MasterLeaguePlan.pro;
    if (plan == MasterLeaguePlan.pro) return MasterLeaguePlan.elite;
    return MasterLeaguePlan.elite;
  }

  // ── Entitlement ───────────────────────────────────────────────────────────

  Future<void> _loadEntitlement() async {
    try {
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);
      final ent =
          await entitlementSvc.getEntitlement(forceRefresh: false);
      final count = await entitlementSvc.countOwnedWorkspaces();
      if (!mounted) return;

      setState(() {
        _activePlan = ent.plan;
        _ownedWorkspaceCount = count;
        _loadingEntitlement = false;
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

  // ── Snack ─────────────────────────────────────────────────────────────────

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
        content: Text(text),
      ),
    );
  }

  // ── Competition draft ─────────────────────────────────────────────────────

  MasterLeagueCompetitionDraft? _buildCompetitionDraft() {
    final competitionName = _competitionNameCtrl.text.trim();
    if (competitionName.isEmpty) {
      _showMessage('Please enter the competition name.',
          error: true);
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

  // ── Upgrade screen entry point ───────────────────────────────────────────
  //
  // The ONLY place this screen ever opens the payment flow. Everything
  // about pricing, plan tiers, duration, and the actual charge lives
  // inside UpgradePlanScreen now.
  Future<bool> _openUpgradeScreen({MasterLeaguePlan? initialPlan}) async {
    if (_processing) return false;

    final suggested =
        initialPlan ?? _nextPlanAbove(_activePlan ?? MasterLeaguePlan.basic);

    final upgraded = await UpgradePlanScreen.open(
      context,
      initialPlan: suggested,
    );

    if (!mounted) return false;

    if (upgraded) {
      await _loadEntitlement();
    }

    return upgraded;
  }

  // ── Create ────────────────────────────────────────────────────────────────
  //
  // No payment happens in this method anymore. It only ever:
  //   - reads the server-verified plan (bypassing local cache),
  //   - creates the workspace against that plan if there's room, or
  //   - sends the user to UpgradePlanScreen if there isn't, then retries.
  Future<void> _create() async {
    if (_processing) return;

    final masterLeagueName = _masterLeagueNameCtrl.text.trim();
    if (masterLeagueName.isEmpty) {
      _showMessage('Please enter a Master League name.',
          error: true);
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
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);

      MasterLeaguePlan? verifiedPlan;
      try {
        verifiedPlan =
            await entitlementSvc.getProfilePlanStrict(forceRefresh: true);
      } catch (_) {
        verifiedPlan = null;
      }

      // No plan on record at all yet — synthesize the implicit free
      // Basic entitlement, same as the old free-plan path used to.
      if (verifiedPlan == null) {
        await entitlementSvc.activateBasicFreePlan();
        verifiedPlan = MasterLeaguePlan.basic;
      }

      var workspaceCount = await entitlementSvc.countOwnedWorkspaces();

      if (!verifiedPlan.canCreateWorkspace(workspaceCount)) {
        final upgraded = await _openUpgradeScreen(
          initialPlan: _nextPlanAbove(verifiedPlan),
        );
        if (!mounted) return;
        if (!upgraded) {
          setState(() => _processing = false);
          return;
        }

        verifiedPlan =
            await entitlementSvc.getProfilePlanStrictWithRetry();
        if (verifiedPlan == null) {
          _showMessage(
            "Your payment went through, but we couldn't confirm your "
            'plan yet. Please wait a moment and tap Create Workspace '
            'again.',
            error: true,
          );
          setState(() => _processing = false);
          return;
        }

        workspaceCount = await entitlementSvc.countOwnedWorkspaces();
        if (!verifiedPlan.canCreateWorkspace(workspaceCount)) {
          _showMessage(
            'You have reached the workspace limit for '
            '${verifiedPlan.displayName} plan.',
            error: true,
          );
          setState(() => _processing = false);
          return;
        }
      }

      final MasterLeaguePlan resolvedPlan = verifiedPlan;

      // ── Diagnostic-only claim check, kept from the previous version
      // so a create failure still tells us whether the organizerPro
      // custom claim landed on this token.
      bool hasOrganizerProClaim = false;
      String claimDebug = '';
      try {
        final tokenResult =
            await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
        final claims = tokenResult?.claims ?? <String, dynamic>{};
        final organizerPro = claims['organizerPro'];
        final organizerProPlan = claims['organizerProPlan'];
        final organizerProExpiryMs = claims['organizerProExpiryMs'];
        hasOrganizerProClaim = organizerPro == true &&
            (organizerProPlan == 'pro' || organizerProPlan == 'elite');
        claimDebug = 'organizerPro=$organizerPro '
            'organizerProPlan=$organizerProPlan '
            'organizerProExpiryMs=$organizerProExpiryMs';
      } catch (e) {
        claimDebug = 'claim check failed: $e';
      }

      final MasterLeague created;
      try {
        created = await repo.create(
          name: masterLeagueName,
          plan: resolvedPlan,
          initialCompetition: competition,
        );
      } catch (e) {
        if (!mounted) return;
        _showMessage(
          '$e\n\n[CLAIM CHECK] hasOrganizerProClaim=$hasOrganizerProClaim '
          '$claimDebug',
          error: true,
        );
        setState(() => _processing = false);
        return;
      }

      if (!mounted) return;
      _showMessage('Master League created successfully.');
      _safeGo('/master-leagues/${created.id}');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CreateML] Create failed: $e');
      }
      if (mounted) _showMessage('$e', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Create Master League'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _safePop,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isDesktop = w >= _BP.desktop;
            final hPad = w < _BP.tablet ? 16.0 : 24.0;

            if (isDesktop) {
              return _buildDesktopLayout(context, hPad);
            }
            return _buildMobileLayout(context, hPad);
          },
        ),
      ),
    );
  }

  // ── Desktop two-column ────────────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context, double hPad) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: hPad, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildFormCard(context),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: _buildActionPanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mobile single column ──────────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context, double hPad) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding:
              EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
          children: [
            _buildFormCard(context),
            const SizedBox(height: 14),
            _buildActionPanel(context),
          ],
        ),
      ),
    );
  }

  // ── Form card ─────────────────────────────────────────────────────────────

  Widget _buildFormCard(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
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
                  color:
                      AppTheme.iconCircleBackground(brightness),
                  border: Border.all(
                      color: AppTheme.cardBorder(brightness)),
                ),
                child: Icon(
                  Icons.hub_rounded,
                  color: AppTheme.limeAccentDark,
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
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Enter a workspace name and first competition name.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildPlanStatusRow(context),
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
    );
  }

  // ── Plan status row ───────────────────────────────────────────────────────

  Widget _buildPlanStatusRow(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (_loadingEntitlement) {
      return Text(
        'Checking active plan...',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (_activePlan != null) {
      return Text(
        'Active plan: ${_activePlan!.displayName} • '
        'Workspaces: $_ownedWorkspaceCount / '
        '${_activePlan!.unlimitedMasterLeagues ? '∞' : '${_activePlan!.maxMasterLeagues}'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.limeAccentDark,
          fontWeight: FontWeight.w900,
        ),
      );
    }
    return Text(
      'No active plan yet — a free Basic workspace will be created.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: AppTheme.secondaryText(brightness),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // ── Action panel ──────────────────────────────────────────────────────────
  //
  // Replaces the old plan-tiles + duration-selector + pay button panel.
  // The ONLY payment entry point on this screen is the "Upgrade Plan"
  // button below, which pushes UpgradePlanScreen. "Create Workspace"
  // never charges anything itself — if it turns out payment is needed,
  // _create() opens the same upgrade screen automatically.

  Widget _buildActionPanel(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Workspace Plan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: AppTheme.primaryText(brightness),
              ),
            ),
          ),

          // ── Upgrade button — always visible, always the only path
          // into the payment flow from this screen.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _processing
                  ? null
                  : () => _openUpgradeScreen(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.limeAccentDark,
                side: BorderSide(
                  color: AppTheme.limeAccentDark.withOpacity(0.45),
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text(
                'Upgrade Plan',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                padding:
                    const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _processing ? null : _create,
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText,
                      ),
                    )
                  : const Icon(Icons.add_circle_outline_rounded),
              label: Text(
                _processing ? 'Processing...' : 'Create Workspace',
                style: const TextStyle(
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'If you hit your workspace limit, Create Workspace will '
              'take you straight to the upgrade screen and finish '
              'creating once payment is confirmed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}