// lib/features/discovery/presentation/competitions_discovery_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/football_category.dart';
import '../../leagues/models/league_format.dart';
import '../data/discovery_providers.dart';

class CompetitionsDiscoveryScreen extends ConsumerWidget {
  const CompetitionsDiscoveryScreen({super.key});

  /// Reads an optional ?category=<FootballCategory.name> or
  /// ?format=<LeagueFormat.name> query param (set when navigating in
  /// from a Home category/type tile) and filters the already-fetched
  /// recent-public-leagues list client-side. Deliberately not a
  /// separate server query: adding a second equality filter alongside
  /// isPrivate == false would still be index-free, but combined with
  /// this screen's existing orderBy(updatedAtMs) it would need a new
  /// composite index per category/format -- filtering the same capped
  /// list client-side avoids that entirely.
  List<League> _applyFilter(List<League> leagues, Uri uri) {
    final categoryParam = uri.queryParameters['category'];
    final formatParam = uri.queryParameters['format'];

    if (categoryParam != null) {
      final match = FootballCategory.values
          .where((c) => c.name == categoryParam)
          .toList();
      if (match.isNotEmpty) {
        return leagues.where((l) => l.footballCategory == match.first).toList();
      }
    }

    if (formatParam != null) {
      final match =
          LeagueFormat.values.where((f) => f.name == formatParam).toList();
      if (match.isNotEmpty) {
        return leagues.where((l) => l.format == match.first).toList();
      }
    }

    return leagues;
  }

  String? _filterTitle(AppLocalizations l10n, Uri uri) {
    final categoryParam = uri.queryParameters['category'];
    if (categoryParam != null) {
      final match = FootballCategory.values
          .where((c) => c.name == categoryParam)
          .toList();
      if (match.isNotEmpty) return match.first.label;
    }

    final formatParam = uri.queryParameters['format'];
    if (formatParam != null) {
      final match =
          LeagueFormat.values.where((f) => f.name == formatParam).toList();
      if (match.isNotEmpty) return l10n.tr(match.first.l10nKey);
    }

    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final competitionsAsync = ref.watch(publicCompetitionsProvider);
    final uri = GoRouterState.of(context).uri;
    final filterTitle = _filterTitle(l10n, uri);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          filterTitle ?? l10n.tr('competitions_discovery_appbar_title'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(publicCompetitionsProvider),
          child: competitionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.tr('competitions_discovery_load_error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            data: (allLeagues) {
              final leagues = _applyFilter(allLeagues, uri);
              if (leagues.isEmpty) {
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.emoji_events_outlined, size: 40, color: AppTheme.secondaryText(brightness)),
                          const SizedBox(height: 12),
                          Text(
                            l10n.tr('competitions_discovery_empty'),
                            style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: leagues.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _CompetitionTile(league: leagues[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompetitionTile extends StatelessWidget {
  const _CompetitionTile({required this.league});
  final League league;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: () => context.push('/leagues/${league.id}'),
      borderRadius: BorderRadius.circular(20),
      child: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.all(14),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.iconCircleBackground(brightness),
                image: league.leagueImageUrl.trim().isNotEmpty
                    ? DecorationImage(image: NetworkImage(league.leagueImageUrl.trim()), fit: BoxFit.cover)
                    : null,
              ),
              child: league.leagueImageUrl.trim().isEmpty
                  ? const Icon(Icons.emoji_events_rounded, color: AppTheme.limeAccentDark)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    league.name,
                    style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryText(brightness)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${league.footballCategory.badgeLabel} • ${league.maxTeams} ${l10n.tr('competitions_discovery_teams_suffix')} • ${league.season}',
                    style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(brightness)),
          ],
        ),
      ),
    );
  }
}