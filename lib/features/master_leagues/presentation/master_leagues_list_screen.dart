import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/logic/league_premium_upgrade_helper.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

class MasterLeaguesListScreen extends ConsumerStatefulWidget {
  const MasterLeaguesListScreen({super.key});

  @override
  ConsumerState<MasterLeaguesListScreen> createState() =>
      _MasterLeaguesListScreenState();
}

class _MasterLeaguesListScreenState
    extends ConsumerState<MasterLeaguesListScreen> {
  bool _loading = true;
  String? _error;

  List<MasterLeague> _created = const <MasterLeague>[];
  List<MasterLeague> _joined = const <MasterLeague>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final created = await repo.fetchCreatedMasterLeaguesOnce();
      final joined = await repo.fetchJoinedMasterLeaguesOnce();

      if (!mounted) return;
      setState(() {
        _created = created;
        _joined = joined;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _created = const [];
        _joined = const [];
        _loading = false;
        _error = '$e';
      });
    }
  }

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
          content: Text('Plan upgraded successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _sectionTitle(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterLeagueList(
    BuildContext context,
    List<MasterLeague> items,
  ) {
    if (items.isEmpty) {
      return const EmptyState(
        title: 'No Master Leagues yet',
        message:
            'Create your first organizer workspace to manage competitions in one place.',
        icon: Icons.hub_rounded,
      );
    }

    return Column(
      children: List.generate(items.length, (i) {
        final ml = items[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
          child: MasterLeagueCard(
            masterLeague: ml,
            onTap: () => context.push('/master-leagues/${ml.id}'),
          ),
        );
      }),
    );
  }

  String _planStatusText(MasterLeaguePlan? plan, UserPlanSubscription? sub) {
    if (plan == null || sub == null) return 'No active plan detected.';
    if (plan.isFree) return 'Active plan: ${plan.displayName} (Free)';
    return 'Active plan: ${plan.displayName} • ${sub.duration.displayName} • ${sub.daysRemaining} days remaining';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final planAsync = ref.watch(organizerProActivePlanProvider);
    final subAsync = ref.watch(userPlanSubscriptionProvider);
    final workspaceCountAsync = ref.watch(ownedWorkspaceCountProvider);
    final shouldShowPayAsync = ref.watch(shouldShowWorkspacePaymentProvider);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Master Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Create Master League',
            onPressed: () => context.push('/master-leagues/create'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/master-leagues/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
                children: [
                  Glass(
                    borderRadius: 30,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Organizer Workspaces',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create and manage Master Leagues for your organizer brand, competitions, staff, and announcements.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.72),
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        planAsync.when(
                          loading: () => Text(
                            'Checking active plan...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          error: (_, __) => Text(
                            'Unable to verify active plan right now.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          data: (plan) {
                            final sub = subAsync.valueOrNull;
                            return Text(
                              _planStatusText(plan, sub),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: plan == null
                                    ? cs.onSurface.withOpacity(0.68)
                                    : cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        workspaceCountAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (count) {
                            final plan = planAsync.valueOrNull;
                            final maxLabel = (plan != null &&
                                    plan.unlimitedMasterLeagues)
                                ? '∞'
                                : '${plan?.maxMasterLeagues ?? '?'}';
                            return Text(
                              'Workspaces: $count / $maxLabel',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.72),
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          },
                        ),
                        subAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
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
                                    color: const Color(0xFFF59E0B)
                                        .withOpacity(0.30),
                                  ),
                                ),
                                child: Text(
                                  'Your ${sub.plan.displayName} plan expires in ${sub.daysRemaining} days. Renew to keep access.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFF59E0B),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        shouldShowPayAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (showPay) {
                            if (!showPay) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: FilledButton.icon(
                                onPressed: _openInlineUpgrade,
                                icon: const Icon(Icons.workspace_premium_rounded),
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
                  ),
                  const SizedBox(height: 18),
                  if (_loading) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ] else ...[
                    if (_error != null)
                      Glass(
                        borderRadius: 22,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    _sectionTitle(
                      context,
                      title: 'Created by You',
                      subtitle: 'Master Leagues you own and manage.',
                    ),
                    _created.isEmpty
                        ? const EmptyState(
                            title: 'No Master Leagues yet',
                            message:
                                'You have not created any organizer workspace yet.',
                            icon: Icons.hub_rounded,
                          )
                        : _buildMasterLeagueList(context, _created),
                    const SizedBox(height: 20),
                    _sectionTitle(
                      context,
                      title: 'Joined Workspaces',
                      subtitle:
                          'Master Leagues where you are a member, admin, or moderator.',
                    ),
                    _joined.isEmpty
                        ? const EmptyState(
                            title: 'No joined workspaces',
                            message:
                                'When you are added to an organizer workspace, it will appear here.',
                            icon: Icons.groups_outlined,
                          )
                        : _buildMasterLeagueList(context, _joined),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
