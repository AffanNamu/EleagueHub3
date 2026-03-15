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
      final aMs =
          a.createdAt?.millisecondsSinceEpoch ?? a.updatedAtMs;
      final bMs =
          b.createdAt?.millisecondsSinceEpoch ?? b.updatedAtMs;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final createdAsync = ref.watch(createdMasterLeaguesProvider);
    final joinedAsync = ref.watch(joinedMasterLeaguesProvider);
    final unlockedAsync = ref.watch(masterLeagueUnlockedProvider);
    final planAsync = ref.watch(organizerProActivePlanProvider);

    Widget header() {
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
        borderRadius: 28,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Master Leagues',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              statusLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: plan != null ? cs.primary : cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Create a Master League, complete Flutterwave payment, and your league will be created only after secure verification. You can also view leagues you joined here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
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
      required List<MasterLeague> items,
      required String emptyTitle,
      required String emptyMessage,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
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
            constraints: const BoxConstraints(maxWidth: 720),
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

                    return ListView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
                      children: [
                        header(),
                        const SizedBox(height: 14),
                        buildSection(
                          title: 'Created by You',
                          items: created,
                          emptyTitle: 'No created Master Leagues yet',
                          emptyMessage:
                              'When you complete payment and create one, it will appear here.',
                        ),
                        const SizedBox(height: 18),
                        buildSection(
                          title: 'Joined by You',
                          items: joined,
                          emptyTitle: 'No joined Master Leagues yet',
                          emptyMessage:
                              'Master Leagues where you are added as staff or member will appear here.',
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
}
