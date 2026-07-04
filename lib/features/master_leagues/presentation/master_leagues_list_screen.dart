// lib/features/master_leagues/presentation/master_league_list_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/logic/league_premium_upgrade_helper.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet  = 760;
  static const double desktop = 900;
}

// ---------------------------------------------------------------------------
// MasterLeaguesListScreen
// ---------------------------------------------------------------------------

class MasterLeaguesListScreen extends ConsumerStatefulWidget {
  const MasterLeaguesListScreen({super.key});

  @override
  ConsumerState<MasterLeaguesListScreen> createState() =>
      _MasterLeaguesListScreenState();
}

class _MasterLeaguesListScreenState
    extends ConsumerState<MasterLeaguesListScreen> {
  bool    _loading = true;
  String? _error;

  List<MasterLeague> _created = const <MasterLeague>[];
  List<MasterLeague> _joined  = const <MasterLeague>[];

  bool _checkingCreateAccess = false;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
    // Trigger badge sync for existing users on screen open.
    // Errors are caught inside syncBadgesForCurrentUser — never throws.
    _syncBadgesQuietly();
  }

  // ── badge sync ─────────────────────────────────────────────────────────────

  Future<void> _syncBadgesQuietly() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) return;
      await UserProfileRepository().syncBadgesForCurrentUser();
    } catch (_) {
      // Silent — badge sync must never affect the UI.
    }
  }

  // ── safe navigation ────────────────────────────────────────────────────────

  void _safePush(String location) {
    try {
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint('[MasterLeaguesList] push($location) failed: $e');
    }
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error   = null;
      });
    }

    try {
      final repo    = ref.read(masterLeaguesRepositoryProvider);
      final created = await repo.fetchCreatedMasterLeaguesOnce();
      final joined  = await repo.fetchJoinedMasterLeaguesOnce();

      if (!mounted) return;
      setState(() {
        _created = created;
        _joined  = joined;
        _loading = false;
        _error   = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _created = const [];
        _joined  = const [];
        _loading = false;
        _error   = '$e';
      });
    }
  }

  // ── create button gating ──────────────────────────────────────────────────
  //
  // The Create action (app bar icon + FAB) must NOT always go straight to
  // the creation screen.  Per business rules:
  //
  //   • Basic  with 0 workspaces  → create directly (free)
  //   • Pro    with < 5 slots     → create directly (included in plan)
  //   • Elite                     → always create directly (unlimited)
  //   • Basic at limit (1)  OR
  //     Pro   at limit (5)        → open upgrade / payment sheet
  //
  // FIXED: We now check BOTH the entitlement service (claims-based) AND the
  // user profile (Firestore-based) so that Google Play users whose custom
  // claims have not yet been set by the async RTDN webhook are NOT falsely
  // blocked.  If either source says the user has an active plan we respect it.
  //
  // If every check fails (network outage, unauthenticated) we fail open to
  // the creation screen itself, which has its own sign-in guard.

  Future<void> _handleCreateTap() async {
    if (_checkingCreateAccess) return;

    setState(() => _checkingCreateAccess = true);

    bool canCreate = true;

    try {
      // ── Primary check: entitlement service (claims + profile) ──────────
      final entitlementSvc =
          ref.read(masterLeagueEntitlementServiceProvider);
      canCreate = await entitlementSvc.canCreateWorkspace();
    } catch (e) {
      debugPrint(
        '[MasterLeaguesList] entitlement canCreateWorkspace '
        'failed: $e — falling back to profile check.',
      );

      // ── Fallback: read directly from the Firestore profile ─────────────
      // This covers Google Play users whose claims are not yet populated.
      try {
        final uid =
            FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
        if (uid.isNotEmpty) {
          final repo = ref.read(userProfileRepositoryProvider);
          final profile = await repo.fetchByUserIdForBootstrap(uid);
          if (profile != null && profile.hasPlanActive) {
            // User has an active plan — check workspace slot availability
            // directly from plan limits vs current workspace count.
            final plan = profile.activePlan;
            if (plan != null) {
              if (plan.unlimitedMasterLeagues) {
                canCreate = true;
              } else {
                final count = _created.length; // already loaded above
                canCreate = plan.canCreateWorkspace(count);
              }
            } else {
              // Profile says premium but plan not parsed — fail open.
              canCreate = true;
            }
          } else {
            // No active plan — only basic free workspace allowed.
            canCreate = _created.isEmpty;
          }
        }
      } catch (fallbackErr) {
        debugPrint(
          '[MasterLeaguesList] profile fallback check failed: '
          '$fallbackErr — failing open.',
        );
        canCreate = true;
      }
    }

    if (!mounted) return;
    setState(() => _checkingCreateAccess = false);

    if (canCreate) {
      _safePush('/master-leagues/create');
      return;
    }

    // At limit — send the user to upgrade instead of the creation screen.
    await _openInlineUpgrade();
  }

  // ── upgrade ────────────────────────────────────────────────────────────────

  Future<void> _openInlineUpgrade() async {
    final ok = await LeaguePremiumUpgradeHelper.openUpgradeFlow(
      context,
      leagueName: 'Organizer Plan',
    );
    if (!mounted) return;
    if (ok) {
      // Invalidate plan providers so the header card refreshes immediately.
      ref.invalidate(organizerProActivePlanProvider);
      ref.invalidate(userPlanSubscriptionProvider);
      ref.invalidate(ownedWorkspaceCountProvider);
      ref.invalidate(shouldShowWorkspacePaymentProvider);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:  Text('Plan upgraded successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String _planStatusText(
    MasterLeaguePlan? plan,
    UserPlanSubscription? sub,
  ) {
    if (plan == null || sub == null) {
      return 'No active plan detected.';
    }
    if (plan.isFree) {
      return 'Active plan: ${plan.displayName} (Free)';
    }
    return 'Active plan: ${plan.displayName} • '
        '${sub.duration.displayName} • '
        '${sub.daysRemaining} days remaining';
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    // Watch providers — these auto-refresh when Firestore data changes,
    // which covers the Google Play post-purchase state update.
    final planAsync           = ref.watch(organizerProActivePlanProvider);
    final subAsync            = ref.watch(userPlanSubscriptionProvider);
    final workspaceCountAsync = ref.watch(ownedWorkspaceCountProvider);
    final shouldShowPayAsync  =
        ref.watch(shouldShowWorkspacePaymentProvider);

    return GlassScaffold(
      appBar: AppBar(
        title:           const Text('Master Leagues'),
        backgroundColor: Colors.transparent,
        elevation:       0,
        actions: [
          IconButton(
            tooltip:  'Create Master League',
            onPressed: _checkingCreateAccess ? null : _handleCreateTap,
            icon: _checkingCreateAccess
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow:    AppTheme.fabGlow(brightness),
        ),
        child: FloatingActionButton.extended(
          backgroundColor: AppTheme.limeAccent,
          foregroundColor: AppTheme.darkText,
          onPressed: _checkingCreateAccess ? null : _handleCreateTap,
          icon: _checkingCreateAccess
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.darkText,
                  ),
                )
              : const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Invalidate async providers so they re-fetch on pull-to-refresh.
            ref.invalidate(organizerProActivePlanProvider);
            ref.invalidate(userPlanSubscriptionProvider);
            ref.invalidate(ownedWorkspaceCountProvider);
            ref.invalidate(shouldShowWorkspacePaymentProvider);
            await _load();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w         = constraints.maxWidth;
              final isDesktop = w >= _BP.desktop;
              final hPad      = w < _BP.tablet ? 16.0 : 24.0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                    hPad, 12, hPad, 100),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1100 : 780,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Info / plan header card ──────────────────────
                        _buildInfoCard(
                          context:             context,
                          theme:               theme,
                          brightness:          brightness,
                          planAsync:           planAsync,
                          subAsync:            subAsync,
                          workspaceCountAsync: workspaceCountAsync,
                          shouldShowPayAsync:  shouldShowPayAsync,
                        ),
                        const SizedBox(height: 18),

                        // ── Loading / error / content ────────────────────
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else ...[
                          if (_error != null)
                            Glass(
                              borderRadius: 22,
                              padding:     const EdgeInsets.all(16),
                              fill: AppTheme.cardColor(brightness),
                              borderColor:
                                  AppTheme.cardBorder(brightness),
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),

                          _sectionTitle(
                            context,
                            title:    'Created by You',
                            subtitle:
                                'Master Leagues you own and manage.',
                          ),
                          _buildResponsiveList(
                            context,
                            items:       _created,
                            emptyTitle:  'No Master Leagues yet',
                            emptyMessage:
                                'You have not created any organizer '
                                'workspace yet.',
                            emptyIcon:  Icons.hub_rounded,
                            isDesktop:  isDesktop,
                          ),
                          const SizedBox(height: 20),

                          _sectionTitle(
                            context,
                            title:    'Joined Workspaces',
                            subtitle:
                                'Master Leagues where you are a '
                                'member, admin, or moderator.',
                          ),
                          _buildResponsiveList(
                            context,
                            items:       _joined,
                            emptyTitle:  'No joined workspaces',
                            emptyMessage:
                                'When you are added to an organizer '
                                'workspace, it will appear here.',
                            emptyIcon:  Icons.groups_outlined,
                            isDesktop:  isDesktop,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── User identity row (name + verification badge) ─────────────────────────
  //
  // Shows who is signed in and their current verification badge.
  // Uses the Riverpod currentUserProfileStreamProvider so that badge
  // state updates (e.g. immediately after a plan purchase) are reflected
  // without a manual refresh.

  Widget _buildUserIdentityRow(Brightness brightness) {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    // Use the Riverpod stream provider (already set up in providers file)
    // instead of creating a raw UserProfileRepository() — this respects
    // the auth guard and shares the same stream across the widget tree.
    final profileAsync =
        ref.watch(currentUserProfileStreamProvider);

    return profileAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(
              Icons.account_circle_rounded,
              size:  18,
              color: AppTheme.secondaryText(brightness),
            ),
            const SizedBox(width: 6),
            Text(
              'Loading...',
              style: TextStyle(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w700,
                fontSize:   12.5,
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) {
        // Resolve display name from profile → auth → fallback.
        final String name;
        if (profile != null &&
            profile.teamName.trim().isNotEmpty) {
          name = profile.teamName.trim();
        } else {
          final authName = FirebaseAuth
              .instance.currentUser?.displayName
              ?.trim();
          name = (authName != null && authName.isNotEmpty)
              ? authName
              : 'You';
        }

        // Determine badge label for the tooltip shown next to the name.
        // Pro  → green verified badge
        // Elite → gold organizer badge (highest priority shown)
        final String? badgeLabel = profile == null
            ? null
            : profile.isOrganizerVerified
                ? 'Elite Organizer'
                : profile.isGreenVerified
                    ? 'Pro Verified'
                    : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(
                Icons.account_circle_rounded,
                size:  18,
                color: AppTheme.secondaryText(brightness),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Signed in as $name',
                  style: TextStyle(
                    color:      AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                    fontSize:   12.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // VerificationBadgeWidget streams badge state independently —
              // it will update as soon as BadgeRepository writes the new
              // badge after plan activation.
              VerificationBadgeWidget(userId: uid, size: 15),
              if (badgeLabel != null) ...[
                const SizedBox(width: 4),
                Text(
                  badgeLabel,
                  style: TextStyle(
                    color: profile!.isOrganizerVerified
                        ? const Color(0xFFFFB300)
                        : const Color(0xFF00C853),
                    fontWeight: FontWeight.w800,
                    fontSize:   11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Info / plan header card ────────────────────────────────────────────────

  Widget _buildInfoCard({
    required BuildContext context,
    required ThemeData theme,
    required Brightness brightness,
    required AsyncValue<MasterLeaguePlan?> planAsync,
    required AsyncValue<UserPlanSubscription?> subAsync,
    required AsyncValue<int> workspaceCountAsync,
    required AsyncValue<bool> shouldShowPayAsync,
  }) {
    // FIXED: Also watch the real-time user profile stream so that the
    // plan status text reflects the Firestore profile immediately after
    // a Google Play purchase — before the claims-based providers update.
    final profileAsync = ref.watch(currentUserProfileStreamProvider);

    return Glass(
      borderRadius: 30,
      padding:     const EdgeInsets.all(18),
      fill:        AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserIdentityRow(brightness),
          Text(
            'Organizer Workspaces',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight:    FontWeight.w900,
              letterSpacing: -0.35,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create and manage Master Leagues for your organizer '
            'brand, competitions, staff, and announcements.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:      AppTheme.secondaryText(brightness),
              height:     1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // ── Active plan text ─────────────────────────────────────────
          // We try the claims-based provider first (planAsync). If it
          // says no plan, we fall back to the profile stream — this
          // covers Google Play users whose claims are not yet set.
          _buildPlanStatusText(
            theme:        theme,
            brightness:   brightness,
            planAsync:    planAsync,
            subAsync:     subAsync,
            profileAsync: profileAsync,
          ),
          const SizedBox(height: 6),

          // ── Workspace count ──────────────────────────────────────────
          workspaceCountAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (count) {
              // Resolve plan from claims provider first, then profile.
              final plan = planAsync.valueOrNull
                  ?? profileAsync.valueOrNull?.activePlan;
              final maxLabel =
                  (plan != null && plan.unlimitedMasterLeagues)
                      ? '∞'
                      : '${plan?.maxMasterLeagues ?? '?'}';
              return Text(
                'Workspaces: $count / $maxLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:      AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),

          // ── Expiry warning ───────────────────────────────────────────
          _buildExpiryWarning(
            theme:        theme,
            subAsync:     subAsync,
            profileAsync: profileAsync,
          ),

          // ── Upgrade button ───────────────────────────────────────────
          shouldShowPayAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (showPay) {
              // Double-check: if the profile stream says the user has
              // an active paid plan, never show the upgrade button even
              // if the claims-based provider disagrees.
              final profileHasPlan = profileAsync
                      .valueOrNull
                      ?.hasPlanActive ??
                  false;
              final profilePlanIsPaid =
                  profileAsync.valueOrNull?.activePlan?.isFree ==
                      false;

              if (!showPay ||
                  (profileHasPlan && profilePlanIsPaid)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _openInlineUpgrade,
                  icon: const Icon(
                      Icons.workspace_premium_rounded),
                  label: const Text(
                    'Upgrade Plan',
                    style:
                        TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Plan status text (claims → profile fallback) ──────────────────────────

  Widget _buildPlanStatusText({
    required ThemeData theme,
    required Brightness brightness,
    required AsyncValue<MasterLeaguePlan?> planAsync,
    required AsyncValue<UserPlanSubscription?> subAsync,
    required AsyncValue<UserProfile?> profileAsync,
  }) {
    // While loading, show spinner text.
    if (planAsync.isLoading) {
      return Text(
        'Checking active plan...',
        style: theme.textTheme.bodySmall?.copyWith(
          color:      AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
      );
    }

    // Try claims-based plan first.
    MasterLeaguePlan? plan = planAsync.valueOrNull;
    UserPlanSubscription? sub = subAsync.valueOrNull;

    // Fallback: read from profile stream (Google Play users).
    if (plan == null) {
      final profile = profileAsync.valueOrNull;
      if (profile != null) {
        plan = profile.activePlan;
        sub  = profile.planSubscription;
      }
    }

    if (plan == null) {
      return Text(
        'No active plan detected.',
        style: theme.textTheme.bodySmall?.copyWith(
          color:      AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return Text(
      _planStatusText(plan, sub),
      style: theme.textTheme.bodySmall?.copyWith(
        color:      AppTheme.limeAccentDark,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  // ── Expiry warning (claims → profile fallback) ────────────────────────────

  Widget _buildExpiryWarning({
    required ThemeData theme,
    required AsyncValue<UserPlanSubscription?> subAsync,
    required AsyncValue<UserProfile?> profileAsync,
  }) {
    // Try claims-based subscription first; fall back to profile.
    UserPlanSubscription? sub = subAsync.valueOrNull;
    if (sub == null) {
      sub = profileAsync.valueOrNull?.planSubscription;
    }

    if (sub == null || !sub.isExpiringSoon) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF59E0B).withOpacity(0.28),
          ),
        ),
        child: Text(
          'Your ${sub.plan.displayName} plan expires in '
          '${sub.daysRemaining} days. Renew to keep access.',
          style: theme.textTheme.bodySmall?.copyWith(
            color:      const Color(0xFFF59E0B),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── Section title ──────────────────────────────────────────────────────────

  Widget _sectionTitle(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight:    FontWeight.w900,
              letterSpacing: -0.2,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color:      AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Responsive list / grid ─────────────────────────────────────────────────

  Widget _buildResponsiveList(
    BuildContext context, {
    required List<MasterLeague> items,
    required String emptyTitle,
    required String emptyMessage,
    required IconData emptyIcon,
    required bool isDesktop,
  }) {
    if (items.isEmpty) {
      return EmptyState(
        title:   emptyTitle,
        message: emptyMessage,
        icon:    emptyIcon,
      );
    }

    if (isDesktop && items.length > 1) {
      return Wrap(
        spacing:    16,
        runSpacing: 16,
        children: items.map((ml) {
          return SizedBox(
            width: 500,
            child: MasterLeagueCard(
              masterLeague: ml,
              onTap: () => _safePush('/master-leagues/${ml.id}'),
            ),
          );
        }).toList(),
      );
    }

    return Column(
      children: List.generate(items.length, (i) {
        final ml = items[i];
        return Padding(
          padding: EdgeInsets.only(
              bottom: i == items.length - 1 ? 0 : 12),
          child: MasterLeagueCard(
            masterLeague: ml,
            onTap: () => _safePush('/master-leagues/${ml.id}'),
          ),
        );
      }),
    );
  }
}