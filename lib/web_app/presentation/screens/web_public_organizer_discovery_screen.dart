import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../features/master_leagues/domain/master_league.dart';
import '../../../features/master_leagues/logic/master_leagues_providers.dart';
import '../../../features/master_leagues/presentation/widgets/master_league_card.dart';

class WebPublicOrganizerDiscoveryScreen extends ConsumerWidget {
  const WebPublicOrganizerDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 1100;

    final featuredAsync = ref.watch(featuredOrganizerWorkspacesProvider);
    final verifiedAsync = ref.watch(verifiedOrganizerWorkspacesProvider);
    final recentAsync = ref.watch(recentActiveOrganizerWorkspacesProvider);
    final allAsync = ref.watch(allOrganizerWorkspacesProvider);

    Widget section({
      required String title,
      required String subtitle,
      required AsyncValue<List<MasterLeague>> data,
      required String emptyTitle,
      required String emptyMessage,
      required IconData icon,
      Widget? trailing,
    }) {
      return Glass(
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: data.when(
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppTheme.limeAccentDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Unable to load this section right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          data: (items) {
            final visibleItems =
                trailing == null ? items : items.take(6).toList(growable: false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.limeAccentDark),
                    const SizedBox(width: 10),
                    Expanded(
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
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 14),
                if (visibleItems.isEmpty)
                  EmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    icon: Icons.hub_rounded,
                  )
                else
                  ...List.generate(visibleItems.length, (i) {
                    final ml = visibleItems[i];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == visibleItems.length - 1 ? 0 : 12,
                      ),
                      child: MasterLeagueCard(
                        masterLeague: ml,
                        onTap: () => context.push('/master-leagues/${ml.id}'),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      );
    }

    Future<void> refresh() async {
      ref.invalidate(featuredOrganizerWorkspacesProvider);
      ref.invalidate(verifiedOrganizerWorkspacesProvider);
      ref.invalidate(recentActiveOrganizerWorkspacesProvider);
      ref.invalidate(allOrganizerWorkspacesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Organizer Discovery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  Glass(
                    borderRadius: 30,
                    padding: const EdgeInsets.all(20),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Organizers',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                            color: AppTheme.primaryText(brightness),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Explore trusted organizer workspaces, discover verified brands, and follow active competition hosts.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.secondaryText(brightness),
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _InfoStat(
                              label: 'Featured',
                              value: featuredAsync.maybeWhen(
                                data: (v) => '${v.length}',
                                orElse: () => '—',
                              ),
                              icon: Icons.star_rounded,
                              color: const Color(0xFFF59E0B),
                              brightness: brightness,
                            ),
                            _InfoStat(
                              label: 'Verified',
                              value: verifiedAsync.maybeWhen(
                                data: (v) => '${v.length}',
                                orElse: () => '—',
                              ),
                              icon: Icons.verified_rounded,
                              color: const Color(0xFF38BDF8),
                              brightness: brightness,
                            ),
                            _InfoStat(
                              label: 'Recently Active',
                              value: recentAsync.maybeWhen(
                                data: (v) => '${v.length}',
                                orElse: () => '—',
                              ),
                              icon: Icons.bolt_rounded,
                              color: const Color(0xFF22C55E),
                              brightness: brightness,
                            ),
                            _InfoStat(
                              label: 'All Organizers',
                              value: allAsync.maybeWhen(
                                data: (v) => '${v.length}',
                                orElse: () => '—',
                              ),
                              icon: Icons.hub_rounded,
                              color: AppTheme.limeAccentDark,
                              brightness: brightness,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (isCompact) ...[
                    section(
                      title: 'Featured Organizers',
                      subtitle: 'Admin-picked or top organizer workspaces.',
                      data: featuredAsync,
                      emptyTitle: 'No featured organizers yet',
                      emptyMessage: 'Featured organizers will appear here.',
                      icon: Icons.star_rounded,
                    ),
                    const SizedBox(height: 18),
                    section(
                      title: 'Verified Organizers',
                      subtitle:
                          'Trusted organizer workspaces with verification badges.',
                      data: verifiedAsync,
                      emptyTitle: 'No verified organizers yet',
                      emptyMessage:
                          'Verified organizers will appear here once approved.',
                      icon: Icons.verified_rounded,
                    ),
                    const SizedBox(height: 18),
                    section(
                      title: 'Recently Active Organizers',
                      subtitle: 'Workspaces with recent activity and updates.',
                      data: recentAsync,
                      emptyTitle: 'No active organizers yet',
                      emptyMessage:
                          'Recently active organizer workspaces will appear here.',
                      icon: Icons.bolt_rounded,
                    ),
                    const SizedBox(height: 18),
                    section(
                      title: 'All Organizers',
                      subtitle: 'All organizer workspaces on the platform.',
                      data: allAsync,
                      emptyTitle: 'No organizers yet',
                      emptyMessage:
                          'Organizer workspaces will appear here as they are created.',
                      icon: Icons.hub_rounded,
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: section(
                            title: 'Featured Organizers',
                            subtitle: 'Admin-picked or top organizer workspaces.',
                            data: featuredAsync,
                            emptyTitle: 'No featured organizers yet',
                            emptyMessage: 'Featured organizers will appear here.',
                            icon: Icons.star_rounded,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: section(
                            title: 'Verified Organizers',
                            subtitle:
                                'Trusted organizer workspaces with verification badges.',
                            data: verifiedAsync,
                            emptyTitle: 'No verified organizers yet',
                            emptyMessage:
                                'Verified organizers will appear here once approved.',
                            icon: Icons.verified_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: section(
                            title: 'Recently Active Organizers',
                            subtitle: 'Workspaces with recent activity and updates.',
                            data: recentAsync,
                            emptyTitle: 'No active organizers yet',
                            emptyMessage:
                                'Recently active organizer workspaces will appear here.',
                            icon: Icons.bolt_rounded,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: section(
                            title: 'All Organizers',
                            subtitle: 'All organizer workspaces on the platform.',
                            data: allAsync,
                            emptyTitle: 'No organizers yet',
                            emptyMessage:
                                'Organizer workspaces will appear here as they are created.',
                            icon: Icons.hub_rounded,
                          ),
                        ),
                      ],
                    ),
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

class _InfoStat extends StatelessWidget {
  const _InfoStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.brightness,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      fill: AppTheme.searchBackground(brightness),
      borderColor: AppTheme.searchOutline(brightness),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
