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

  List<MasterLeague> _sort(List<MasterLeague> input) {
    final sorted = [...input];
    sorted.sort((a, b) {
      final aMs = a.createdAt?.millisecondsSinceEpoch ?? a.updatedAtMs;
      final bMs = b.createdAt?.millisecondsSinceEpoch ?? b.updatedAtMs;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  int _workspacePower(List<MasterLeague> leagues) {
    int total = 0;
    for (final ml in leagues) {
      total += ml.analytics.totalTournamentsCreated;
      total += ml.analytics.totalParticipantsTeams;
      total += ml.analytics.totalMatches;
    }
    return total;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final createdAsync = ref.watch(createdMasterLeaguesProvider);
    final joinedAsync = ref.watch(joinedMasterLeaguesProvider);
    final unlockedAsync = ref.watch(masterLeagueUnlockedProvider);
    final planAsync = ref.watch(organizerProActivePlanProvider);

    Widget header({
      required int createdCount,
      required int joinedCount,
      required int workspacePower,
    }) {
      final unlocked = unlockedAsync.asData?.value == true;
      final plan = planAsync.asData?.value;

      final String statusLine;
      if (plan != null) {
        statusLine = 'Organizer Pro active • Plan: ${plan.displayName}';
      } else if (unlocked) {
        statusLine = 'Organizer Pro active';
      } else {
        statusLine = 'You can pay during Master League creation';
      }

      return Glass(
        borderRadius: 30,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organizer Workspace',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.35,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              statusLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: plan != null
                    ? cs.primary
                    : cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Master Leagues are organizer workspaces. Create competitions, manage staff, build trust with verification, and operate your organizer identity in one place.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.72),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metricChip(
                  context,
                  icon: Icons.hub_rounded,
                  label: '$createdCount created',
                ),
                _metricChip(
                  context,
                  icon: Icons.group_outlined,
                  label: '$joinedCount joined',
                ),
                _metricChip(
                  context,
                  icon: Icons.bolt_rounded,
                  label: 'Workspace power $workspacePower',
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.push('/master-leagues/create'),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text(
                'Create Master League',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSection({
      required String title,
      required String subtitle,
      required List<MasterLeague> items,
      required String emptyTitle,
      required String emptyMessage,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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
          ),
          if (items.isEmpty)
            EmptyState(
              title: emptyTitle,
              message: emptyMessage,
              icon: Icons.hub_rounded,
            )
          else
            ...List.generate(items.length, (i) {
              final ml = items[i];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : 12,
                ),
                child: MasterLeagueCard(
                  masterLeague: ml,
                  onTap: () => context.push('/master-leagues/${ml.id}'),
                ),
              );
            }),
        ],
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: createdAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '$e',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              data: (createdRaw) {
                return joinedAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '$e',
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  data: (joinedRaw) {
                    final created = _sort(createdRaw);
                    final joined = _sort(joinedRaw);
                    final power = _workspacePower([...created, ...joined]);

                    return ListView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
                      children: [
                        header(
                          createdCount: created.length,
                          joinedCount: joined.length,
                          workspacePower: power,
                        ),
                        const SizedBox(height: 16),
                        buildSection(
                          title: 'Workspaces You Own',
                          subtitle:
                              'These are your main organizer hubs for creating and managing competitions.',
                          items: created,
                          emptyTitle: 'No organizer workspaces yet',
                          emptyMessage:
                              'Create your first Master League to launch your organizer workspace.',
                        ),
                        const SizedBox(height: 20),
                        buildSection(
                          title: 'Workspaces You Joined',
                          subtitle:
                              'Master Leagues where you were added as staff or member.',
                          items: joined,
                          emptyTitle: 'No joined workspaces yet',
                          emptyMessage:
                              'When an organizer adds you to a Master League, it will appear here.',
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/master-leagues/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }

  Widget _metricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.08),
        border: Border.all(color: cs.primary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
