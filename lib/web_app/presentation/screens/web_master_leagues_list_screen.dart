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

  Widget _buildWorkspaceGrid(List<MasterLeague> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: EmptyState(
          title: 'No Workspaces Found',
          message: 'You have not created or joined any workspaces yet.',
          icon: Icons.hub_rounded,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 180,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final ml = items[index];
        return MasterLeagueCard(
          masterLeague: ml,
          onTap: () => context.push('/master-leagues/${ml.id}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final planAsync = ref.watch(organizerProActivePlanProvider);
    final subAsync = ref.watch(userPlanSubscriptionProvider);
    final workspaceCountAsync = ref.watch(ownedWorkspaceCountProvider);
    final shouldShowPayAsync = ref.watch(shouldShowWorkspacePaymentProvider);

    return GlassScaffold(
      useBubbles: false,
      appBar: AppBar(
        title: const Text('Workspaces Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Glass(
                        borderRadius: 24,
                        padding: const EdgeInsets.all(32),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Organizer Hub',
                                    style: TextStyle(
                                      color: AppTheme.primaryText(brightness),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Manage your master brands, staffs, and premium competitions seamlessly.',
                                    style: TextStyle(
                                      color: AppTheme.secondaryText(brightness),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.limeAccent,
                                foregroundColor: AppTheme.darkText,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => context.push('/master-leagues/create'),
                              icon: const Icon(Icons.add_circle_outline_rounded),
                              label: const Text('CREATE WORKSPACE', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              title: 'Active Plan',
                              value: planAsync.when(
                                data: (p) => p?.displayName ?? 'Basic',
                                loading: () => 'Loading...',
                                error: (_, __) => 'Error',
                              ),
                              icon: Icons.workspace_premium_rounded,
                              brightness: brightness,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatCard(
                              title: 'Workspaces Used',
                              value: workspaceCountAsync.when(
                                data: (count) {
                                  final plan = planAsync.valueOrNull;
                                  final max = (plan != null && plan.unlimitedMasterLeagues) ? '∞' : '${plan?.maxMasterLeagues ?? '?'}';
                                  return '$count / $max';
                                },
                                loading: () => 'Loading...',
                                error: (_, __) => 'Error',
                              ),
                              icon: Icons.pie_chart_outline_rounded,
                              brightness: brightness,
                            ),
                          ),
                          if (shouldShowPayAsync.valueOrNull == true) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: _openInlineUpgrade,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: AppTheme.limeAccentDark.withOpacity(0.1),
                                    border: Border.all(color: AppTheme.limeAccentDark),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.arrow_upward_rounded, color: AppTheme.limeAccentDark, size: 28),
                                      SizedBox(height: 12),
                                      Text('Upgrade Now', style: TextStyle(color: AppTheme.limeAccentDark, fontWeight: FontWeight.w900, fontSize: 18)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w900))
                      else ...[
                        Text('Owned Workspaces', style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w900, fontSize: 22)),
                        const SizedBox(height: 16),
                        _buildWorkspaceGrid(_created),
                        const SizedBox(height: 40),
                        Text('Joined Workspaces', style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w900, fontSize: 22)),
                        const SizedBox(height: 16),
                        _buildWorkspaceGrid(_joined),
                      ],
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
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Brightness brightness;

  const _StatCard({required this.title, required this.value, required this.icon, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(brightness),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.secondaryText(brightness), size: 28),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}
