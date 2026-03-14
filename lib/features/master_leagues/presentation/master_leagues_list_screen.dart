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
        statusLine = 'Organizer Pro not active';
      }

      return Glass(
        borderRadius: 28,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organizer Pro Mode',
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
                color: plan != null
                    ? cs.primary
                    : cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Master Leagues let you organize multiple competitions (Classic, Swiss, UCL Group) '
              'inside one professional organizer system. Subscription checks are enforced server-side.',
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

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Organizer Pro'),
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
            child: listAsync.when(
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
              data: (list) {
                final sorted = [...list];
                sorted.sort((a, b) {
                  final dynamic ad = a.createdAt;
                  final dynamic bd = b.createdAt;

                  int aMs = 0;
                  int bMs = 0;

                  if (ad is DateTime) aMs = ad.millisecondsSinceEpoch;
                  if (bd is DateTime) bMs = bd.millisecondsSinceEpoch;

                  try {
                    if (ad != null && ad.millisecondsSinceEpoch is int) {
                      aMs = ad.millisecondsSinceEpoch as int;
                    }
                  } catch (_) {}

                  try {
                    if (bd != null && bd.millisecondsSinceEpoch is int) {
                      bMs = bd.millisecondsSinceEpoch as int;
                    }
                  } catch (_) {}

                  return bMs.compareTo(aMs);
                });

                return ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
                  children: [
                    header(),
                    const SizedBox(height: 14),
                    if (sorted.isEmpty)
                      const EmptyState(
                        title: 'No Master Leagues yet',
                        message:
                            'Create one to manage multiple competitions under one organizer system.',
                        icon: Icons.hub_rounded,
                      )
                    else ...[
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 4, bottom: 10, top: 4),
                        child: Text(
                          'Your Master Leagues',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      ...List.generate(sorted.length, (i) {
                        final ml = sorted[i];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: i == sorted.length - 1 ? 0 : 12,
                          ),
                          child: MasterLeagueCard(
                            masterLeague: ml,
                            onTap: () =>
                                context.push('/master-leagues/${ml.id}'),
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
        onPressed: () => context.push('/master-leagues/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }
}
