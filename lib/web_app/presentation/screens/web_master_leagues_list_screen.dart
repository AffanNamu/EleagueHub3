import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/leagues/logic/league_premium_upgrade_helper.dart';
import '../../../features/master_leagues/domain/master_league.dart';
import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../../features/master_leagues/logic/master_leagues_providers.dart';
import '../../../features/master_leagues/presentation/widgets/master_league_card.dart';

class WebMasterLeaguesListScreen extends ConsumerStatefulWidget {
  const WebMasterLeaguesListScreen({super.key});

  @override
  ConsumerState<WebMasterLeaguesListScreen> createState() =>
      _WebMasterLeaguesListScreenState();
}

class _WebMasterLeaguesListScreenState
    extends ConsumerState<WebMasterLeaguesListScreen> {
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

  String _planStatusText(MasterLeaguePlan? plan, UserPlanSubscription? sub) {
    if (plan == null || sub == null) return 'No active plan detected.';
    if (plan.isFree) return 'Active plan: ${plan.displayName} (Free)';
    return 'Active plan: ${plan.displayName} • ${sub.duration.displayName} • ${sub.daysRemaining} days remaining';
  }

  Widget _sectionTitle(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
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

  Widget _statTile({
    required Brightness brightness,
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Glass(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.12),
              border: Border.all(color: accent.withOpacity(0.24)),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(
    ThemeData theme,
    Brightness brightness,
    AsyncValue<MasterLeaguePlan?> planAsync,
    AsyncValue<UserPlanSubscription?> subAsync,
    AsyncValue<int> workspaceCountAsync,
    AsyncValue<bool> shouldShowPayAsync,
  ) {
    return Glass(
      borderRadius: 30,
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organizer Workspaces',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: AppTheme.primaryText(brightness),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create and manage Master Leagues for your organizer brand, competitions, staff, and announcements.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          planAsync.when(
            loading: () => Text(
              'Checking active plan...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
              ),
            ),
            error: (_, __) => Text(
              'Unable to verify active plan right now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
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
          workspaceCountAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (count) {
              final plan = planAsync.valueOrNull;
              final maxLabel =
                  (plan != null && plan.unlimitedMasterLeagues)
                      ? '∞'
                      : '${plan?.maxMasterLeagues ?? '?'}';
              return Text(
                'Workspaces: $count / $maxLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
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
                padding: const EdgeInsets.only(top: 10),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => context.push('/master-leagues/create'),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Create Workspace',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Refresh',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              shouldShowPayAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (showPay) {
                  if (!showPay) return const SizedBox.shrink();
                  return FilledButton.tonalIcon(
                    onPressed: _openInlineUpgrade,
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text(
                      'Upgrade Plan',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ThemeData theme, Brightness brightness) {
    if (_error == null) return const SizedBox.shrink();
    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Text(
        _error!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 1080;

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
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Create Master League',
            onPressed: () => context.push('/master-leagues/create'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1380),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  _heroCard(
                    theme,
                    brightness,
                    planAsync,
                    subAsync,
                    workspaceCountAsync,
                    shouldShowPayAsync,
                  ),
                  const SizedBox(height: 16),
                  if (!_loading)
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isCompact ? 2 : 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isCompact ? 2.1 : 2.35,
                      children: [
                        _statTile(
                          brightness: brightness,
                          icon: Icons.hub_rounded,
                          label: 'Created',
                          value: '${_created.length}',
                          accent: AppTheme.limeAccentDark,
                        ),
                        _statTile(
                          brightness: brightness,
                          icon: Icons.groups_rounded,
                          label: 'Joined',
                          value: '${_joined.length}',
                          accent: const Color(0xFF38BDF8),
                        ),
                        _statTile(
                          brightness: brightness,
                          icon: Icons.workspace_premium_rounded,
                          label: 'Plan',
                          value: planAsync.valueOrNull?.displayName ?? 'None',
                          accent: const Color(0xFF8B5CF6),
                        ),
                        _statTile(
                          brightness: brightness,
                          icon: Icons.inventory_2_outlined,
                          label: 'Workspace Slots',
                          value: workspaceCountAsync.maybeWhen(
                            data: (count) {
                              final plan = planAsync.valueOrNull;
                              final max = (plan != null &&
                                      plan.unlimitedMasterLeagues)
                                  ? '∞'
                                  : '${plan?.maxMasterLeagues ?? '?'}';
                              return '$count/$max';
                            },
                            orElse: () => '—',
                          ),
                          accent: const Color(0xFF22C55E),
                        ),
                      ],
                    ),
                  if (!_loading) const SizedBox(height: 16),
                  _errorCard(theme, brightness),
                  if (_error != null) const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Glass(
                          borderRadius: 24,
                          padding: const EdgeInsets.all(16),
                          fill: AppTheme.cardColor(brightness),
                          borderColor: AppTheme.cardBorder(brightness),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(
                                context,
                                title: 'Created by You',
                                subtitle: 'Master Leagues you own and manage.',
                              ),
                              const SizedBox(height: 14),
                              _created.isEmpty
                                  ? const EmptyState(
                                      title: 'No Master Leagues yet',
                                      message:
                                          'You have not created any organizer workspace yet.',
                                      icon: Icons.hub_rounded,
                                    )
                                  : _buildMasterLeagueList(context, _created),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Glass(
                          borderRadius: 24,
                          padding: const EdgeInsets.all(16),
                          fill: AppTheme.cardColor(brightness),
                          borderColor: AppTheme.cardBorder(brightness),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(
                                context,
                                title: 'Joined Workspaces',
                                subtitle:
                                    'Master Leagues where you are a member, admin, or moderator.',
                              ),
                              const SizedBox(height: 14),
                              _joined.isEmpty
                                  ? const EmptyState(
                                      title: 'No joined workspaces',
                                      message:
                                          'When you are added to an organizer workspace, it will appear here.',
                                      icon: Icons.groups_outlined,
                                    )
                                  : _buildMasterLeagueList(context, _joined),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(16),
                            fill: AppTheme.cardColor(brightness),
                            borderColor: AppTheme.cardBorder(brightness),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle(
                                  context,
                                  title: 'Created by You',
                                  subtitle: 'Master Leagues you own and manage.',
                                ),
                                const SizedBox(height: 14),
                                _created.isEmpty
                                    ? const EmptyState(
                                        title: 'No Master Leagues yet',
                                        message:
                                            'You have not created any organizer workspace yet.',
                                        icon: Icons.hub_rounded,
                                      )
                                    : _buildMasterLeagueList(context, _created),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(16),
                            fill: AppTheme.cardColor(brightness),
                            borderColor: AppTheme.cardBorder(brightness),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle(
                                  context,
                                  title: 'Joined Workspaces',
                                  subtitle:
                                      'Master Leagues where you are a member, admin, or moderator.',
                                ),
                                const SizedBox(height: 14),
                                _joined.isEmpty
                                    ? const EmptyState(
                                        title: 'No joined workspaces',
                                        message:
                                            'When you are added to an organizer workspace, it will appear here.',
                                        icon: Icons.groups_outlined,
                                      )
                                    : _buildMasterLeagueList(context, _joined),
                              ],
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
      ),
    );
  }
}
