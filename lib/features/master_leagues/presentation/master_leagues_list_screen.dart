import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

class MasterLeaguesListScreen extends ConsumerWidget {
  const MasterLeaguesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final createdAsync = ref.watch(createdMasterLeaguesProvider);
    final joinedAsync = ref.watch(joinedMasterLeaguesProvider);
    final planAsync = ref.watch(organizerProActivePlanProvider);

    Widget sectionTitle(String title, String subtitle) {
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

    Widget buildMasterLeagueList(List<MasterLeague> items) {
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

    Widget loadingCard() {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    Widget safeErrorCard(String title) {
      return Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(16),
        child: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.error,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

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
              onRefresh: () async {
                ref.invalidate(createdMasterLeaguesProvider);
                ref.invalidate(joinedMasterLeaguesProvider);
                ref.invalidate(organizerProActivePlanProvider);
                await Future<void>.delayed(const Duration(milliseconds: 250));
              },
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
                          data: (plan) => Text(
                            plan == null
                                ? 'No active Organizer Pro plan detected.'
                                : 'Active plan: ${plan.displayName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: plan == null ? cs.onSurface.withOpacity(0.68) : cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  sectionTitle(
                    'Created by You',
                    'Master Leagues you own and manage.',
                  ),
                  createdAsync.when(
                    loading: () => loadingCard(),
                    error: (_, __) => safeErrorCard(
                      'Unable to load your created Master Leagues right now.',
                    ),
                    data: buildMasterLeagueList,
                  ),

                  const SizedBox(height: 20),

                  sectionTitle(
                    'Joined Workspaces',
                    'Master Leagues where you are a member, admin, or moderator.',
                  ),
                  joinedAsync.when(
                    loading: () => loadingCard(),
                    error: (_, __) => safeErrorCard(
                      'Unable to load joined Master Leagues right now.',
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return const EmptyState(
                          title: 'No joined workspaces',
                          message:
                              'When you are added to an organizer workspace, it will appear here.',
                          icon: Icons.groups_outlined,
                        );
                      }
                      return buildMasterLeagueList(items);
                    },
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
