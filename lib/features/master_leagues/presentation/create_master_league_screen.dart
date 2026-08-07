// lib/features/master_leagues/presentation/create_master_league_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
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

  MasterLeaguePlan _selectedPlan = MasterLeaguePlan.basic;
  PlanDuration _selectedDuration = PlanDuration.threeMonths;
  MasterLeaguePlan? _activePlan;
  int _ownedWorkspaceCount = 0;

  String _lastVerifiedAttemptId = '';
  String _lastVerifiedPaymentId = '';
  String _lastVerifiedReceiptId = '';

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

  // ── Payment guards ────────────────────────────────────────────────────────

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

  // ── Inline upgrade ────────────────────────────────────────────────────────

  Future<bool> _openInlineUpgrade() async {
    final paymentSvc =
        ref.read(masterLeaguePaymentServiceProvider);
    final entitlementSvc =
        ref.read(masterLeagueEntitlementServiceProvider);
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    if (uid.isEmpty) {
      _showMessage('Please sign in and try again.', error: true);
      return false;
    }

    _lastVerifiedAttemptId = '';
    _lastVerifiedPaymentId = '';
    _lastVerifiedReceiptId = '';

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
      // For Google Play, payForPlanSubscription() returns the purchase
      // token in txRef (see FlutterwaveMasterLeaguePaymentService.
      // _purchasePlanViaGooglePlay). The worker needs this to verify
      // the purchase server-side. Harmless no-op for Flutterwave.
      purchaseToken: result.txRef,
    );

    _lastVerifiedAttemptId = result.attemptId;
    _lastVerifiedPaymentId = result.paymentId;
    final resolvedReceiptId = (result.receiptId ?? '').trim();
    _lastVerifiedReceiptId = resolvedReceiptId.isNotEmpty
        ? resolvedReceiptId
        : (result.paymentId.trim().isNotEmpty
            ? result.paymentId.trim()
            : result.attemptId.trim());

    await _loadEntitlement();
    return true;
  }

  // ── Create ────────────────────────────────────────────────────────────────
  //
  // FIXED (regression #2 — mobile Google Play purchasers could not
  // create a workspace even after a successful payment, and existing
  // Pro/Elite users could hit the same permission-denied error).
  //
  // Root cause: MasterLeagueEntitlementService._isGooglePlayProvider()
  // only matched the literal string 'google_play_billing'.
  // MasterLeaguesRepositoryFirebase and firestore.rules (validProvider())
  // both also accept plain 'google_play'. Whenever the payment SDK
  // reported the provider as 'google_play', activateAfterPayment() fell
  // through to the Flutterwave/web worker branch instead of writing the
  // Firestore profile directly — so users/{uid}.activePlanId never got
  // set for that purchase, even though the in-app purchase itself
  // succeeded. Since Google Play purchases never receive the
  // organizerPro custom claim (only the Flutterwave worker sets that),
  // firestore.rules' profileHasActivePlan() was the ONLY thing that
  // could authorize the master_leagues create — and it always failed,
  // producing "You don't have access to this Master League...".
  // _isGooglePlayProvider() has been fixed to accept both provider
  // strings.
  //
  // Belt-and-suspenders fix here: this method no longer trusts
  // `_selectedPlan` directly after a payment (or trusts a single
  // cached entitlement read for an existing plan holder). It ALWAYS
  // re-resolves the plan to WRITE via
  // entitlementSvc.getProfilePlanStrictWithRetry(), which reads
  // users/{uid} straight from the Firestore server (bypassing the
  // mobile offline-persistence cache) and retries briefly to absorb
  // any short propagation delay right after activation. That is the
  // exact same data firestore.rules' profileHasActivePlan() will
  // independently check at write time, so the two checks can never
  // drift apart again — regardless of provider string or timing.
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
      final repo =
          ref.read(masterLeaguesRepositoryProvider);
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);

      final currentEnt = await entitlementSvc.getEntitlement(
          forceRefresh: true);
      final effectivePlan = currentEnt.plan ?? _selectedPlan;
      final currentWorkspaceCount =
          await entitlementSvc.countOwnedWorkspaces();

      // ── Free plan path ───────────────────────────────────────────────────
      if (_selectedPlan.isFree) {
        if (!effectivePlan.canCreateWorkspace(currentWorkspaceCount)) {
          _showMessage(
            'You have reached the workspace limit for '
            '${effectivePlan.displayName} plan.',
            error: true,
          );
          if (mounted) setState(() => _processing = false);
          return;
        }

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
        _safeGo('/master-leagues/${created.id}');
        return;
      }

      // ── Paid plan path ───────────────────────────────────────────────────
      // ── FIXED (regression #3): "do we even need a payment" was still
      // being decided from `effectivePlan`, which comes from
      // getEntitlement() -> _readFromProfile() -> the cacheable
      // repository call. Per that code's own comments, this can still
      // serve a locally-cached read on mobile instead of the true
      // server document. That meant an existing paying user (confirmed
      // valid `activePlanId` on the server) could still be routed into
      // the payment/re-verification flow purely because the local
      // cache hadn't caught up — a needless, unpredictable detour
      // (Google Play "already owned" edge cases, etc.) instead of just
      // creating the workspace. This is decided from a STRICT,
      // server-verified read first now; the loose signal is only a
      // fallback for when that strict read can't run at all (e.g.
      // offline).
      MasterLeaguePlan? verifiedPlanForDecision;
      try {
        verifiedPlanForDecision =
            await entitlementSvc.getProfilePlanStrict(forceRefresh: true);
      } catch (_) {
        verifiedPlanForDecision = null;
      }

      final bool needsPaymentNow;
      if (verifiedPlanForDecision != null &&
          _planOrder(verifiedPlanForDecision) >= _planOrder(_selectedPlan)) {
        // Server-confirmed: the user already holds a plan at or above
        // the one they selected. The only remaining question is
        // capacity.
        needsPaymentNow = !verifiedPlanForDecision
            .canCreateWorkspace(currentWorkspaceCount);
      } else {
        // No server-confirmed plan at the required tier (or the
        // strict check couldn't run). Fall back to the lighter
        // entitlement signal just to decide whether to show the
        // payment flow — a stale "yes" here is still caught by the
        // write-time verification below; a stale "no" just means we
        // show the payment screen when it may not strictly have been
        // necessary.
        needsPaymentNow =
            !effectivePlan.canCreateWorkspace(currentWorkspaceCount) ||
                _planOrder(effectivePlan) < _planOrder(_selectedPlan);
      }

      if (needsPaymentNow) {
        final upgraded = await _openInlineUpgrade();
        if (!mounted) return;
        if (!upgraded) {
          setState(() => _processing = false);
          return;
        }
      }

      // ── FIXED: resolve the plan to WRITE strictly and ALWAYS from a
      // fresh, server-verified read of the Firestore profile — with
      // retries so a just-completed payment has time to propagate.
      // Never trust `_selectedPlan` directly, even right after a
      // successful payment (see the method-level comment above for why
      // that trust was unsafe). If we already have a strict,
      // still-valid read from the check just above (no payment was
      // needed), reuse it instead of a redundant round-trip.
      MasterLeaguePlan? writePlan = (!needsPaymentNow &&
              verifiedPlanForDecision != null &&
              _planOrder(verifiedPlanForDecision) >=
                  _planOrder(_selectedPlan))
          ? verifiedPlanForDecision
          : await entitlementSvc.getProfilePlanStrictWithRetry();

      if (writePlan == null) {
        if (needsPaymentNow) {
          // A payment was just verified this attempt, but the profile
          // doesn't reflect it yet. Do NOT trigger another charge —
          // just ask the user to retry the create in a moment.
          if (!mounted) return;
          _showMessage(
            "Your payment went through, but we couldn't confirm your "
            'plan yet. Please wait a moment and tap Create Workspace '
            'again.',
            error: true,
          );
          setState(() => _processing = false);
          return;
        }

        // The profile genuinely has no active paid plan right now
        // (expired, or was never activated) — a payment IS actually
        // required, even though our earlier (looser) entitlement check
        // thought otherwise. Fall through to the upgrade flow instead
        // of writing a value that's guaranteed to be denied.
        final upgraded = await _openInlineUpgrade();
        if (!mounted) return;
        if (!upgraded) {
          setState(() => _processing = false);
          return;
        }

        writePlan = await entitlementSvc.getProfilePlanStrictWithRetry();
        if (writePlan == null) {
          if (!mounted) return;
          _showMessage(
            "Your payment went through, but we couldn't confirm your "
            'plan yet. Please wait a moment and tap Create Workspace '
            'again.',
            error: true,
          );
          setState(() => _processing = false);
          return;
        }
      }

      final MasterLeaguePlan resolvedPlan = writePlan;

      final refreshedWorkspaceCount =
          await entitlementSvc.countOwnedWorkspaces();

      if (!resolvedPlan.canCreateWorkspace(refreshedWorkspaceCount)) {
        _showMessage(
          'You have reached the workspace limit for '
          '${resolvedPlan.displayName} plan.',
          error: true,
        );
        setState(() => _processing = false);
        return;
      }

      if (needsPaymentNow &&
          (_lastVerifiedAttemptId.trim().isEmpty ||
              _lastVerifiedPaymentId.trim().isEmpty ||
              _lastVerifiedReceiptId.trim().isEmpty)) {
        final retried = await _openInlineUpgrade();
        if (!mounted) return;
        if (!retried ||
            _lastVerifiedAttemptId.trim().isEmpty ||
            _lastVerifiedPaymentId.trim().isEmpty ||
            _lastVerifiedReceiptId.trim().isEmpty) {
          _showMessage(
            'We could not confirm your payment. Please try again, '
            'or contact support if you were charged.',
            error: true,
          );
          setState(() => _processing = false);
          return;
        }
      }

      final MasterLeague created;
      if (needsPaymentNow) {
        created = await repo.createAfterVerifiedPayment(
          masterLeagueName: masterLeagueName,
          plan: resolvedPlan,
          attemptId: _lastVerifiedAttemptId,
          paymentId: _lastVerifiedPaymentId,
          receiptId: _lastVerifiedReceiptId,
          competition: competition,
        );
      } else {
        // User already has an active plan with room to spare — create
        // directly using the STRICT, server-verified plan value, so it
        // is guaranteed to match profile.data.activePlanId exactly.
        created = await repo.create(
          name: masterLeagueName,
          plan: resolvedPlan,
          initialCompetition: competition,
        );
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
                child: _buildPlanSidePanel(context),
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
            _buildPlanSidePanel(context),
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
      'No active plan. Select a plan below.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: AppTheme.secondaryText(brightness),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // ── Plan side panel ───────────────────────────────────────────────────────

  Widget _buildPlanSidePanel(BuildContext context) {
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
              'Choose Plan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: AppTheme.primaryText(brightness),
              ),
            ),
          ),
          ...MasterLeaguePlan.values.map(_buildPlanTile),
          _buildDurationSelector(),
          const SizedBox(height: 8),
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
                  : Icon(
                      _shouldShowPaymentButton
                          ? Icons.payment_rounded
                          : Icons.add_circle_outline_rounded,
                    ),
              label: Text(
                _processing
                    ? 'Processing...'
                    : (_shouldShowPaymentButton
                        ? 'Choose Plan & Pay'
                        : 'Create Workspace'),
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
              _selectedPlan.isFree
                  ? 'Basic plan is free. Your workspace will be '
                    'created instantly.'
                  : 'If you hit your limit, choose another plan '
                    'and pay without leaving this screen.',
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

  // ── Plan tile ─────────────────────────────────────────────────────────────

  Widget _buildPlanTile(MasterLeaguePlan plan) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isSelected = _selectedPlan == plan;
    final isCurrent = _activePlan == plan;
    final lockedLowerPlan = !_canSelectPlan(plan);

    final Color borderColor = isSelected
        ? AppTheme.limeAccentDark
        : AppTheme.cardBorder(brightness);

    final Color bgColor = isSelected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.10)
            : const Color(0xFFECFCCB))
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: lockedLowerPlan ? 0.55 : 1.0,
        child: InkWell(
          onTap: (_processing || lockedLowerPlan)
              ? null
              : () =>
                  setState(() => _selectedPlan = plan),
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
                          ? AppTheme.limeAccentDark
                          : AppTheme.secondaryText(brightness),
                      width: 2,
                    ),
                    color: isSelected
                        ? AppTheme.limeAccent
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          size: 16, color: AppTheme.darkText)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment:
                            WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            plan.displayName,
                            style: theme
                                .textTheme.titleSmall
                                ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryText(
                                  brightness),
                            ),
                          ),
                          if (plan.isPopular)
                            _planBadge('MOST POPULAR',
                                const Color(0xFF22C55E)),
                          if (isCurrent)
                            _currentBadge(brightness),
                          if (plan.isFree)
                            _planBadge(
                                'FREE',
                                const Color(0xFF22C55E)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                          color: AppTheme.secondaryText(
                              brightness),
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

  Widget _planBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Widget _currentBadge(Brightness brightness) {
    final bg = brightness == Brightness.dark
        ? AppTheme.limeAccentDark.withOpacity(0.12)
        : const Color(0xFFECFCCB);
    final border = brightness == Brightness.dark
        ? AppTheme.limeAccentDark.withOpacity(0.26)
        : const Color(0xFFD9F99D);
    final textColor = brightness == Brightness.dark
        ? AppTheme.limeAccent
        : AppTheme.darkText;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        'CURRENT',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: textColor,
        ),
      ),
    );
  }

  // ── Duration selector ─────────────────────────────────────────────────────

  Widget _buildDurationSelector() {
    if (!_selectedNeedsPayment) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Padding(
          padding:
              const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Choose Duration',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: AppTheme.primaryText(brightness),
            ),
          ),
        ),
        ...PlanDuration.values.map((dur) {
          final isSelected = _selectedDuration == dur;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _processing
                  ? null
                  : () => setState(
                      () => _selectedDuration = dur),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration:
                    const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isSelected
                      ? (brightness == Brightness.dark
                          ? AppTheme.limeAccentDark
                              .withOpacity(0.10)
                          : const Color(0xFFECFCCB))
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.limeAccentDark
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
                          ? AppTheme.limeAccentDark
                          : AppTheme.secondaryText(
                              brightness),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dur.displayName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(
                              brightness),
                        ),
                      ),
                    ),
                    if (dur.hasDiscount)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E)
                              .withOpacity(0.12),
                          borderRadius:
                              BorderRadius.circular(8),
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
    );
  }
}