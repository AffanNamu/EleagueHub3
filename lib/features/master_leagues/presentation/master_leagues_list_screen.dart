import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/logic/league_premium_upgrade_helper.dart';
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

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
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

  // ── upgrade ────────────────────────────────────────────────────────────────

  Future<void> _openInlineUpgrade() async {
    final ok = await LeaguePremiumUpgradeHelper.openUpgradeFlow(
      context,
      leagueName: 'Organizer Plan',
    );
    if (!mounted) return;
    if (ok) {
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
      MasterLeaguePlan? plan, UserPlanSubscription? sub) {
    if (plan == null || sub == null) return 'No active plan detected.';
    if (plan.isFree) return 'Active plan: ${plan.displayName} (Free)';
    return 'Active plan: ${plan.displayName} • '
        '${sub.duration.displayName} • '
        '${sub.daysRemaining} days remaining';
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

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
            onPressed: () => _safePush('/master-leagues/create'),
            icon: const Icon(Icons.add_circle_outline_rounded),
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
          onPressed:       () => _safePush('/master-leagues/create'),
          icon:            const Icon(Icons.add),
          label:           const Text('Create'),
        ),
      ),
      body: SafeArea(
        // RefreshIndicator must wrap the full-width scroll area.
        // ConstrainedBox is applied INSIDE so the pull-to-refresh
        // gesture is detected across the entire screen width, not
        // only the 780px content column.
        child: RefreshIndicator(
          onRefresh: _load,
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
                    // Wider on desktop — two-col grid uses the space
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1100 : 780,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Info / plan header card ──────────────────────
                        _buildInfoCard(
                          context:            context,
                          theme:              theme,
                          brightness:         brightness,
                          planAsync:          planAsync,
                          subAsync:           subAsync,
                          workspaceCountAsync: workspaceCountAsync,
                          shouldShowPayAsync: shouldShowPayAsync,
                        ),
                        const SizedBox(height: 18),

                        // ── Loading / error / content ────────────────────
                        if (_loading)
                          const Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                                child: CircularProgressIndicator()),
                          )
                        else ...[
                          if (_error != null)
                            Glass(
                              borderRadius: 22,
                              padding: const EdgeInsets.all(16),
                              fill: AppTheme.cardColor(brightness),
                              borderColor:
                                  AppTheme.cardBorder(brightness),
                              child: Text(
                                _error!,
                                style:
                                    theme.textTheme.bodyMedium?.copyWith(
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
                            items:     _created,
                            emptyTitle:   'No Master Leagues yet',
                            emptyMessage:
                                'You have not created any organizer '
                                'workspace yet.',
                            emptyIcon: Icons.hub_rounded,
                            isDesktop: isDesktop,
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
                            items:     _joined,
                            emptyTitle:   'No joined workspaces',
                            emptyMessage:
                                'When you are added to an organizer '
                                'workspace, it will appear here.',
                            emptyIcon: Icons.groups_outlined,
                            isDesktop: isDesktop,
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
    return Glass(
      borderRadius: 30,
      padding:      const EdgeInsets.all(18),
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

          // Active plan text
          planAsync.when(
            loading: () => Text(
              'Checking active plan...',
              style: theme.textTheme.bodySmall?.copyWith(
                color:      AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
            error: (_, __) => Text(
              'Unable to verify active plan right now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:      theme.colorScheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
            data: (plan) {
              final sub = subAsync.valueOrNull;
              return Text(
                _planStatusText(plan, sub),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: plan == null
                      ? AppTheme.secondaryText(brightness)
                      : AppTheme.limeAccentDark,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
          const SizedBox(height: 6),

          // Workspace count
          workspaceCountAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (count) {
              final plan     = planAsync.valueOrNull;
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

          // Expiry warning
          subAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (sub) {
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
            },
          ),

          // Upgrade button
          shouldShowPayAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (showPay) {
              if (!showPay) return const SizedBox.shrink();
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
                  icon:  const Icon(Icons.workspace_premium_rounded),
                  label: const Text(
                    'Upgrade Plan',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );
            },
          ),
        ],
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
  // Mobile:  vertical Column of cards (full width)
  // Desktop: 2-column Wrap — each card takes ~half the available width

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
      // Two-column grid via Wrap — simpler than GridView inside a
      // SingleChildScrollView and handles odd item counts correctly.
      return Wrap(
        spacing:    16,
        runSpacing: 16,
        children: items.map((ml) {
          return SizedBox(
            // Each card takes slightly less than half the container
            // so the 16px spacing fits. LayoutBuilder would be more
            // precise but this is clean and predictable.
            width: 500,
            child: MasterLeagueCard(
              masterLeague: ml,
              onTap: () => _safePush('/master-leagues/${ml.id}'),
            ),
          );
        }).toList(),
      );
    }

    // Single column — mobile / tablet / single item on desktop
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
