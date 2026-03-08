import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

class MasterLeaguesListScreen extends ConsumerWidget {
  const MasterLeaguesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final listAsync = ref.watch(myMasterLeaguesProvider);

    Widget header() {
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
              'A premium container that lets you create multiple competitions '
              '(Classic, Swiss, UCL Group) without paying again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  context.push('/master-leagues/create'),
              icon:
                  const Icon(Icons.add_circle_outline_rounded),
              label: const Text(
                'Create Master League',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
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
            onPressed: () =>
                context.push('/master-leagues/create'),
            icon:
                const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: listAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  borderRadius: 28,
                  child: Text(
                    '$e',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              data: (list) {
                return ListView(
                  physics: const BouncingScrollPhysics(
                    parent:
                        AlwaysScrollableScrollPhysics(),
                  ),
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(
                          16, 12, 16, 110),
                  children: [
                    header(),
                    const SizedBox(height: 14),
                    if (list.isEmpty)
                      const EmptyState(
                        title: 'No Master Leagues yet',
                        message:
                            'Create one to organize multiple competitions in a single premium system.',
                        icon: Icons.hub_rounded,
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 4, bottom: 10, top: 4),
                        child: Text(
                          'Your Master Leagues',
                          style: theme
                              .textTheme.titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      ...List.generate(list.length, (i) {
                        final ml = list[i];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: i == list.length - 1
                                ? 0
                                : 12,
                          ),
                          child: MasterLeagueCard(
                            masterLeague: ml,
                            onTap: () => context.push(
                                '/master-leagues/${ml.id}'),
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('/master-leagues/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }
}
