import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

class PublicOrganizerDiscoveryScreen extends ConsumerWidget {
  const PublicOrganizerDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final featuredAsync = ref.watch(featuredOrganizerWorkspacesProvider);
    final verifiedAsync = ref.watch(verifiedOrganizerWorkspacesProvider);
    final recentAsync = ref.watch(recentActiveOrganizerWorkspacesProvider);

    Widget section({
      required String title,
      required String subtitle,
      required AsyncValue<List<MasterLeague>> data,
      required String emptyTitle,
      required String emptyMessage,
    }) {
      return data.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => Glass(
          borderRadius: 22,
          padding: const EdgeInsets.all(16),
          child: Text(
            'Unable to load this section right now.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        data: (items) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
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
                      onTap: () {
                        try {
                          context.push('/master-leagues/${ml.id}');
                        } catch (_) {}
                      },
                    ),
                  );
                }),
            ],
          );
        },
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Organizer Discovery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(featuredOrganizerWorkspacesProvider);
                ref.invalidate(verifiedOrganizerWorkspacesProvider);
                ref.invalidate(recentActiveOrganizerWorkspacesProvider);
                await Future<void>.delayed(const Duration(milliseconds: 250));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
                children: [
                  Glass(
                    borderRadius: 30,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Organizers',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Explore trusted organizer workspaces, discover verified brands, and follow active competition hosts.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.72),
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  section(
                    title: 'Featured Organizers',
                    subtitle: 'Admin-picked or top organizer workspaces.',
                    data: featuredAsync,
                    emptyTitle: 'No featured organizers yet',
                    emptyMessage: 'Featured organizers will appear here.',
                  ),
                  const SizedBox(height: 20),
                  section(
                    title: 'Verified Organizers',
                    subtitle: 'Trusted organizer workspaces with verification badges.',
                    data: verifiedAsync,
                    emptyTitle: 'No verified organizers yet',
                    emptyMessage: 'Verified organizers will appear here once approved.',
                  ),
                  const SizedBox(height: 20),
                  section(
                    title: 'Recently Active Organizers',
                    subtitle: 'Workspaces with recent activity and updates.',
                    data: recentAsync,
                    emptyTitle: 'No active organizers yet',
                    emptyMessage: 'Recently active organizer workspaces will appear here.',
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
