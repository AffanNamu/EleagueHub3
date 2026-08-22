=// lib/features/discovery/presentation/competitions_discovery_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/football_category.dart';
import '../data/discovery_providers.dart';

class CompetitionsDiscoveryScreen extends ConsumerWidget {
  const CompetitionsDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final competitionsAsync = ref.watch(publicCompetitionsProvider);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Competitions'),
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
                    'Unable to load competitions right now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            data: (leagues) {
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
                            'No public competitions yet.',
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
                    '${league.footballCategory.badgeLabel} • ${league.maxTeams} teams • ${league.season}',
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