// lib/features/home/presentation/widgets/home_dashboard_widgets.dart
//
// Home-tab "quick glance" sections backed by HomeDashboardRepository:
// Coming Up Next (nearest unplayed fixtures), Your Standings (the
// viewer's own position in whichever of their leagues they have a team
// in), and Latest Highlights (most recent approved highlight clip).
// Every one of these renders nothing when there's no real data for it --
// no placeholder/fake rows.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/persistence/prefs_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../highlights/presentation/highlight_player_screen.dart';
import '../../../leagues/data/leagues_repository_local.dart';
import '../../data/home_dashboard_repository.dart';

String _relativeTime(AppLocalizations l10n, DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return l10n.tr('notifications_list_time_just_now');
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}${l10n.tr('notifications_list_time_minutes_ago_suffix')}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}${l10n.tr('notifications_list_time_hours_ago_suffix')}';
  }
  return '${diff.inDays}${l10n.tr('notifications_list_time_days_ago_suffix')}';
}

void _openLeague(BuildContext context, String leagueId) {
  try {
    GoRouter.of(context).push('/leagues/$leagueId');
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// HomeDashboardSection -- owns the repository loads, renders all 3 pieces.
// ---------------------------------------------------------------------------

class HomeDashboardSection extends ConsumerStatefulWidget {
  const HomeDashboardSection({super.key});

  @override
  ConsumerState<HomeDashboardSection> createState() =>
      _HomeDashboardSectionState();
}

class _HomeDashboardSectionState extends ConsumerState<HomeDashboardSection> {
  late final HomeDashboardRepository _repo = HomeDashboardRepository(
    leaguesRepo: LocalLeaguesRepository(ref.read(prefsServiceProvider)),
  );

  // Previously 3 independent futures, each re-scanning the user's leagues
  // (listLeagues() + per-league getTeams/getMatches) from scratch -- now
  // one shared load so the league list and each league's teams/matches
  // are fetched exactly once for all 3 sections combined.
  late final Future<HomeDashboardData> _dashboardFuture =
      _repo.loadDashboard(FirebaseAuth.instance.currentUser?.uid ?? '');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeDashboardData>(
      future: _dashboardFuture,
      builder: (context, snap) {
        final data = snap.data;
        final fixtures = data?.fixtures ?? const <HomeUpcomingFixture>[];
        final standings = data?.standings;
        final highlight = data?.highlight;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fixtures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: _ComingUpNextSection(fixtures: fixtures),
              ),
            if (standings != null || highlight != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  final standingsCard = standings == null
                      ? null
                      : _StandingsCard(summary: standings);
                  final highlightCard = highlight == null
                      ? null
                      : _HighlightCard(data: highlight);

                  if (narrow ||
                      standingsCard == null ||
                      highlightCard == null) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (standingsCard != null) ...[
                            standingsCard,
                            if (highlightCard != null)
                              const SizedBox(height: 16),
                          ],
                          if (highlightCard != null) highlightCard,
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: standingsCard),
                          const SizedBox(width: 16),
                          Expanded(child: highlightCard),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Coming Up Next
// ---------------------------------------------------------------------------

class _ComingUpNextSection extends StatelessWidget {
  const _ComingUpNextSection({required this.fixtures});

  final List<HomeUpcomingFixture> fixtures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final t = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_note_rounded,
                color: AppTheme.limeAccentDark, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Plain English -- new Home section, see the app-wide
                // convention noted on the "Quick Actions" heading.
                'Coming Up Next',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryText(brightness),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Your upcoming fixtures',
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: fixtures.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 96,
          ),
          itemBuilder: (context, i) => _UpcomingFixtureTile(data: fixtures[i]),
        ),
      ],
    );
  }
}

class _UpcomingFixtureTile extends StatelessWidget {
  const _UpcomingFixtureTile({required this.data});

  final HomeUpcomingFixture data;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = context.l10n;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        try {
          GoRouter.of(context)
              .push('/leagues/${data.league.id}/matches/${data.match.id}');
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppTheme.cardColor(brightness),
          border: Border.all(color: AppTheme.cardBorder(brightness)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.homeTeam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    l10n.tr('league_highlights_vs_separator'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryText(brightness),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              data.awayTeam.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              // No stored kickoff time in this app's fixture data yet --
              // show the real round number rather than a fabricated date.
              'Round ${data.match.roundNumber + 1}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondaryText(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Your Standings
// ---------------------------------------------------------------------------

class _StandingsCard extends StatelessWidget {
  const _StandingsCard({required this.summary});

  final HomeStandingsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final league = summary.league;

    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  color: AppTheme.limeAccentDark, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your Standings',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openLeague(context, league.id),
            child: Row(
              children: [
                _LeagueBadge(imageUrl: league.leagueImageUrl, brightness: brightness),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        league.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      Text(
                        '${l10n.tr(league.format.l10nKey)} • ${league.season}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.secondaryText(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppTheme.secondaryText(brightness)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StandingStat(
                  label: 'Position',
                  value: '#${summary.position}',
                ),
              ),
              Expanded(
                child: _StandingStat(
                  label: 'Played',
                  value: '${summary.played}',
                ),
              ),
              Expanded(
                child: _StandingStat(
                  label: 'Points',
                  value: '${summary.points}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StandingStat extends StatelessWidget {
  const _StandingStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppTheme.primaryText(brightness),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.secondaryText(brightness),
          ),
        ),
      ],
    );
  }
}

class _LeagueBadge extends StatelessWidget {
  const _LeagueBadge({required this.imageUrl, required this.brightness});

  final String imageUrl;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    return Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.iconCircleBackground(brightness),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: url.isEmpty
          ? Icon(Icons.emoji_events_outlined,
              size: 16, color: AppTheme.limeAccentDark)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.emoji_events_outlined,
                size: 16,
                color: AppTheme.limeAccentDark,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Latest Highlights
// ---------------------------------------------------------------------------

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.data});

  final HomeLatestHighlight data;

  Future<void> _open(BuildContext context) async {
    final url = data.highlight.secureUrl.trim();
    if (url.isEmpty) return;
    await openHighlightPlayer(
      context,
      videoUrl: url,
      title: '${data.league.name} Highlights',
    );
  }

  String _duration() {
    final secs = data.highlight.duration.round();
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final thumb = data.highlight.thumbnailUrl.trim();

    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_fill_rounded,
                  color: AppTheme.limeAccentDark, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Latest Highlights',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: brightness == Brightness.dark
                              ? AppTheme.darkCard
                              : const Color(0xFFE5E7EB),
                          child: thumb.isEmpty
                              ? null
                              : Image.network(
                                  thumb,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                        ),
                        Container(
                          color: Colors.black.withOpacity(0.18),
                        ),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _duration(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  // Real league name + generic "Highlights" label -- this
                  // app's highlight docs aren't linked to a matchweek/
                  // round label today, so we don't fabricate one.
                  '${data.league.name} Highlights',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
                if (data.highlight.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _relativeTime(
                        l10n, data.highlight.createdAt!.toDate()),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryText(brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
