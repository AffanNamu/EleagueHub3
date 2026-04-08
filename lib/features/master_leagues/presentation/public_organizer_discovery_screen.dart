import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained
// ---------------------------------------------------------------------------

class _BP {
  static const double tablet  = 760;
  static const double desktop = 900;
}

// ---------------------------------------------------------------------------
// PublicOrganizerDiscoveryScreen
// ---------------------------------------------------------------------------

class PublicOrganizerDiscoveryScreen extends ConsumerWidget {
  const PublicOrganizerDiscoveryScreen({super.key});

  // ── safe navigation ────────────────────────────────────────────────────────

  void _safePush(BuildContext context, String location) {
    try {
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint(
          '[OrganizerDiscovery] push($location) failed: $e');
    }
  }

  void _safePop(BuildContext context) {
    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    final featuredAsync =
        ref.watch(featuredOrganizerWorkspacesProvider);
    final verifiedAsync =
        ref.watch(verifiedOrganizerWorkspacesProvider);
    final recentAsync =
        ref.watch(recentActiveOrganizerWorkspacesProvider);
    final allAsync =
        ref.watch(allOrganizerWorkspacesProvider);

    return GlassScaffold(
      appBar: AppBar(
        title:           const Text('Organizer Discovery'),
        backgroundColor: Colors.transparent,
        elevation:       0,
        leading: IconButton(
          icon:     const Icon(Icons.arrow_back),
          tooltip:  'Back',
          onPressed: () => _safePop(context),
        ),
      ),
      body: SafeArea(
        // RefreshIndicator wraps LayoutBuilder + scroll area.
        // ConstrainedBox is placed INSIDE so the pull gesture
        // is detected across the full screen width.
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(
                featuredOrganizerWorkspacesProvider);
            ref.invalidate(
                verifiedOrganizerWorkspacesProvider);
            ref.invalidate(
                recentActiveOrganizerWorkspacesProvider);
            ref.invalidate(allOrganizerWorkspacesProvider);
            await Future<void>.delayed(
                const Duration(milliseconds: 250));
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w         = constraints.maxWidth;
              final isDesktop = w >= _BP.desktop;
              final hPad      = w < _BP.tablet ? 16.0 : 24.0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                    hPad, 12, hPad, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1100 : 780,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // ── Header card ──────────────────────────────────
                        Glass(
                          borderRadius: 30,
                          padding:
                              const EdgeInsets.all(18),
                          fill: AppTheme.cardColor(
                              brightness),
                          borderColor:
                              AppTheme.cardBorder(brightness),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Discover Organizers',
                                style: theme
                                    .textTheme.titleLarge
                                    ?.copyWith(
                                  fontWeight:
                                      FontWeight.w900,
                                  letterSpacing: -0.35,
                                  color:
                                      AppTheme.primaryText(
                                          brightness),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Explore trusted organizer '
                                'workspaces, discover verified '
                                'brands, and follow active '
                                'competition hosts.',
                                style: theme
                                    .textTheme.bodyMedium
                                    ?.copyWith(
                                  color:
                                      AppTheme.secondaryText(
                                          brightness),
                                  height:     1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // ── Sections ─────────────────────────────────────
                        _section(
                          context:    context,
                          ref:        ref,
                          theme:      theme,
                          brightness: brightness,
                          isDesktop:  isDesktop,
                          title:      'Featured Organizers',
                          subtitle:
                              'Admin-picked or top organizer workspaces.',
                          data:        featuredAsync,
                          emptyTitle:  'No featured organizers yet',
                          emptyMessage:
                              'Featured organizers will appear here.',
                        ),
                        const SizedBox(height: 20),

                        _section(
                          context:    context,
                          ref:        ref,
                          theme:      theme,
                          brightness: brightness,
                          isDesktop:  isDesktop,
                          title:      'Verified Organizers',
                          subtitle:
                              'Trusted organizer workspaces with '
                              'verification badges.',
                          data:        verifiedAsync,
                          emptyTitle:  'No verified organizers yet',
                          emptyMessage:
                              'Verified organizers will appear here '
                              'once approved.',
                        ),
                        const SizedBox(height: 20),

                        _section(
                          context:    context,
                          ref:        ref,
                          theme:      theme,
                          brightness: brightness,
                          isDesktop:  isDesktop,
                          title:
                              'Recently Active Organizers',
                          subtitle:
                              'Workspaces with recent activity '
                              'and updates.',
                          data:        recentAsync,
                          emptyTitle:  'No active organizers yet',
                          emptyMessage:
                              'Recently active organizer workspaces '
                              'will appear here.',
                        ),
                        const SizedBox(height: 20),

                        _section(
                          context:    context,
                          ref:        ref,
                          theme:      theme,
                          brightness: brightness,
                          isDesktop:  isDesktop,
                          title:      'All Organizers',
                          subtitle:
                              'All organizer workspaces on '
                              'the platform.',
                          data:        allAsync,
                          emptyTitle:  'No organizers yet',
                          emptyMessage:
                              'Organizer workspaces will appear here '
                              'as they are created.',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Section builder ────────────────────────────────────────────────────────

  Widget _section({
    required BuildContext                    context,
    required WidgetRef                       ref,
    required ThemeData                       theme,
    required Brightness                      brightness,
    required bool                            isDesktop,
    required String                          title,
    required String                          subtitle,
    required AsyncValue<List<MasterLeague>>  data,
    required String                          emptyTitle,
    required String                          emptyMessage,
  }) {
    return data.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Glass(
        borderRadius: 22,
        padding:      const EdgeInsets.all(16),
        fill:         AppTheme.cardColor(brightness),
        borderColor:  AppTheme.cardBorder(brightness),
        child: Text(
          'Unable to load this section right now.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color:      theme.colorScheme.error,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      data: (items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section title
            Padding(
              padding:
                  const EdgeInsets.only(left: 4, bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(
                      fontWeight:    FontWeight.w900,
                      letterSpacing: -0.2,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:      AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            // Empty state
            if (items.isEmpty)
              EmptyState(
                title:   emptyTitle,
                message: emptyMessage,
                icon:    Icons.hub_rounded,
              )
            // Desktop two-column grid
            else if (isDesktop && items.length > 1)
              Wrap(
                spacing:    16,
                runSpacing: 16,
                children: items.map((ml) {
                  return SizedBox(
                    width: 500,
                    child: MasterLeagueCard(
                      masterLeague: ml,
                      onTap: () => _safePush(
                        context,
                        '/master-leagues/${ml.id}',
                      ),
                    ),
                  );
                }).toList(),
              )
            // Mobile / single-item — single column
            else
              Column(
                children: List.generate(items.length, (i) {
                  final ml = items[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i == items.length - 1 ? 0 : 12,
                    ),
                    child: MasterLeagueCard(
                      masterLeague: ml,
                      onTap: () => _safePush(
                        context,
                        '/master-leagues/${ml.id}',
                      ),
                    ),
                  );
                }),
              ),
          ],
        );
      },
    );
  }
}
