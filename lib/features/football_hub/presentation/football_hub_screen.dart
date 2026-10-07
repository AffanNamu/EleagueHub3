// lib/features/football_hub/presentation/football_hub_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/football_api_service.dart';
import '../models/football_fixture.dart';
import '../models/football_league.dart';
import '../models/football_news_article.dart';
import '../models/football_player.dart';
import '../models/football_team.dart';
import '../utils/football_season.dart';
import 'football_following_tab.dart';
import 'football_player_screen.dart';
import 'football_standings_screen.dart';
import 'football_team_screen.dart';

/// Football Hub's own v1 home: Matches (date-grouped fixtures), Leagues
/// (quick access to popular competitions' tables + search for the rest),
/// News (GNews headlines) and Following (teams/players you follow).
///
/// v1 scope only -- AI daily summaries/fixture-difficulty ratings/player
/// radar charts are deliberately not here yet (each needs either a budget
/// decision for LLM calls, or more API-Football quota than the free
/// 100 req/day plan allows). See the session's Football Hub scoping notes.
class FootballHubScreen extends StatefulWidget {
  const FootballHubScreen({super.key});

  @override
  State<FootballHubScreen> createState() => _FootballHubScreenState();
}

class _FootballHubScreenState extends State<FootballHubScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Football Hub'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.limeAccentDark,
          unselectedLabelColor: AppTheme.secondaryText(brightness),
          indicatorColor: AppTheme.limeAccentDark,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Matches'),
            Tab(text: 'Leagues'),
            Tab(text: 'Search'),
            Tab(text: 'News'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: const [
            _MatchesTab(),
            _LeaguesTab(),
            _SearchTab(),
            _NewsTab(),
            FootballFollowingTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Matches tab
// ─────────────────────────────────────────────────────────────────────────

class _MatchesTab extends StatefulWidget {
  const _MatchesTab();

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  final _service = FootballApiService();
  late DateTime _selectedDate;
  late Future<List<FootballFixture>> _future;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _load();
  }

  void _load({bool forceRefresh = false}) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _future = _service.getFixturesByDate(date: dateStr, forceRefresh: forceRefresh);
  }

  void _selectDate(DateTime d) {
    setState(() {
      _selectedDate = d;
      _load();
    });
  }

  Future<void> _refresh() async {
    setState(() => _load(forceRefresh: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Column(
      children: [
        _DateStrip(selectedDate: _selectedDate, onSelect: _selectDate),
        const SizedBox(height: 4),
        Expanded(
          child: FutureBuilder<List<FootballFixture>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      UserFriendlyError.toMessage(snap.error!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                    ),
                  ),
                );
              }
              final fixtures = snap.data ?? const [];
              if (fixtures.isEmpty) {
                return Center(
                  child: Text(
                    'No matches on this date.',
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                );
              }

              final byLeague = <int, List<FootballFixture>>{};
              final leagueOrder = <int>[];
              for (final f in fixtures) {
                if (!byLeague.containsKey(f.leagueId)) {
                  byLeague[f.leagueId] = [];
                  leagueOrder.add(f.leagueId);
                }
                byLeague[f.leagueId]!.add(f);
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: leagueOrder.length,
                  itemBuilder: (context, i) {
                    final leagueId = leagueOrder[i];
                    final group = byLeague[leagueId]!;
                    final first = group.first;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Glass(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (first.leagueLogoUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      first.leagueLogoUrl,
                                      width: 18,
                                      height: 18,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${first.leagueCountry.isNotEmpty ? '${first.leagueCountry} · ' : ''}${first.leagueName}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppTheme.primaryText(brightness),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 18),
                            ...group.map((f) => _FixtureRow(fixture: f, brightness: brightness)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selectedDate, required this.onSelect});
  final DateTime selectedDate;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final today = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day).add(Duration(days: i - 3)),
    );

    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final d = days[i];
          final isSelected = d.year == selectedDate.year && d.month == selectedDate.month && d.day == selectedDate.day;
          final isToday = d.year == today.year && d.month == today.month && d.day == today.day;

          return GestureDetector(
            onTap: () => onSelect(d),
            child: Container(
              width: 52,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.limeAccentDark : AppTheme.tabInactiveBackground(brightness),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEE').format(d),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.black : AppTheme.tabInactiveText(brightness),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d').format(d),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.black : AppTheme.primaryText(brightness),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  const _FixtureRow({required this.fixture, required this.brightness});
  final FootballFixture fixture;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppTheme.primaryText(brightness),
    );

    String centerLabel;
    Color centerColor = AppTheme.secondaryText(brightness);
    if (fixture.isLive) {
      centerLabel = fixture.elapsedMinutes != null ? "${fixture.elapsedMinutes}'" : fixture.statusShort;
      centerColor = const Color(0xFFEF4444);
    } else if (fixture.isFinished) {
      centerLabel = 'FT';
    } else {
      centerLabel = DateFormat('HH:mm').format(fixture.kickoff);
    }

    final showScore = fixture.isLive || fixture.isFinished;

    void openTeam(int teamId, String teamName, String teamLogoUrl) {
      context.push('/football/team/$teamId', extra: {'teamName': teamName, 'teamLogoUrl': teamLogoUrl});
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => openTeam(fixture.homeTeamId, fixture.homeTeamName, fixture.homeTeamLogoUrl),
              child: Row(
                children: [
                  if (fixture.homeTeamLogoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        fixture.homeTeamLogoUrl,
                        width: 18,
                        height: 18,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(fixture.homeTeamName, style: nameStyle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: InkWell(
              onTap: () => context.push('/football/match/${fixture.id}', extra: fixture),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showScore)
                    Text(
                      '${fixture.homeGoals ?? 0} - ${fixture.awayGoals ?? 0}',
                      style: nameStyle,
                      textAlign: TextAlign.center,
                    ),
                  Text(
                    centerLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: centerColor),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => openTeam(fixture.awayTeamId, fixture.awayTeamName, fixture.awayTeamLogoUrl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      fixture.awayTeamName,
                      style: nameStyle,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (fixture.awayTeamLogoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        fixture.awayTeamLogoUrl,
                        width: 18,
                        height: 18,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// News tab
// ─────────────────────────────────────────────────────────────────────────

class _NewsTab extends StatefulWidget {
  const _NewsTab();

  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> {
  final _service = FootballApiService();
  late Future<List<FootballNewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool forceRefresh = false}) {
    _future = _service.getFootballNews(forceRefresh: forceRefresh);
  }

  Future<void> _refresh() async {
    setState(() => _load(forceRefresh: true));
    await _future;
  }

  Future<void> _openArticle(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort -- a failed external launch should never crash the tab.
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return FutureBuilder<List<FootballNewsArticle>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                UserFriendlyError.toMessage(snap.error!),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.secondaryText(brightness)),
              ),
            ),
          );
        }
        final articles = snap.data ?? const [];
        if (articles.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                SizedBox(
                  height: 300,
                  child: Center(
                    child: Text(
                      'No football news right now.',
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            itemCount: articles.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NewsArticleCard(
                article: articles[i],
                brightness: brightness,
                onTap: () => _openArticle(articles[i].url),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewsArticleCard extends StatelessWidget {
  const _NewsArticleCard({
    required this.article,
    required this.brightness,
    required this.onTap,
  });

  final FootballNewsArticle article;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: article.url.isEmpty ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Glass(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  article.imageUrl,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 84, height: 84),
                ),
              ),
            if (article.imageUrl.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title.isEmpty ? 'Untitled' : article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (article.sourceName.isNotEmpty) article.sourceName,
                      if (article.publishedAt != null) DateFormat('MMM d, HH:mm').format(article.publishedAt!),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryText(brightness),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Leagues tab
// ─────────────────────────────────────────────────────────────────────────

class _PopularLeague {
  final int id;
  final String name;
  const _PopularLeague(this.id, this.name);
}

const _popularLeagues = <_PopularLeague>[
  _PopularLeague(39, 'Premier League'),
  _PopularLeague(140, 'La Liga'),
  _PopularLeague(135, 'Serie A'),
  _PopularLeague(78, 'Bundesliga'),
  _PopularLeague(61, 'Ligue 1'),
  _PopularLeague(2, 'Champions League'),
];

class _LeaguesTab extends StatefulWidget {
  const _LeaguesTab();

  @override
  State<_LeaguesTab> createState() => _LeaguesTabState();
}

class _LeaguesTabState extends State<_LeaguesTab> {
  final _service = FootballApiService();
  final _searchController = TextEditingController();
  Future<List<FootballLeagueInfo>>? _searchFuture;
  Timer? _searchDebounce;

  // Debounced (not one network call per keystroke) -- searchLeagues()
  // caches each distinct settled term for a day, but a fast typist still
  // produces a new, never-before-cached substring on every keystroke if
  // nothing debounces the calls first.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  void _runSearch(String query) {
    final q = query.trim();
    if (!mounted) return;
    setState(() {
      _searchFuture = q.length >= 3 ? _service.searchLeagues(search: q) : null;
    });
  }

  void _openStandings(BuildContext context, {required int leagueId, required int season, required String name}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FootballStandingsScreen(leagueId: leagueId, season: season, leagueName: name),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final season = currentFootballSeasonGuess();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(color: AppTheme.primaryText(brightness)),
          decoration: InputDecoration(
            hintText: 'Search leagues (3+ letters)',
            hintStyle: TextStyle(color: AppTheme.secondaryText(brightness)),
            filled: true,
            fillColor: AppTheme.searchBackground(brightness),
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.searchOutline(brightness)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_searchFuture != null)
          FutureBuilder<List<FootballLeagueInfo>>(
            future: _searchFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    UserFriendlyError.toMessage(snap.error!),
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                );
              }
              final results = snap.data ?? const [];
              if (results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No leagues found.',
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                );
              }
              return Column(
                children: results
                    .map(
                      (l) => _LeagueListTile(
                        name: l.name,
                        subtitle: l.countryName,
                        logoUrl: l.logoUrl,
                        onTap: l.currentSeason > 0
                            ? () => _openStandings(context, leagueId: l.id, season: l.currentSeason, name: l.name)
                            : null,
                      ),
                    )
                    .toList(growable: false),
              );
            },
          )
        else ...[
          Text(
            'Popular competitions',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.secondaryText(brightness),
            ),
          ),
          const SizedBox(height: 10),
          ..._popularLeagues.map(
            (l) => _LeagueListTile(
              name: l.name,
              subtitle: null,
              logoUrl: '',
              onTap: () => _openStandings(context, leagueId: l.id, season: season, name: l.name),
            ),
          ),
        ],
      ],
    );
  }
}

class _LeagueListTile extends StatelessWidget {
  const _LeagueListTile({
    required this.name,
    required this.subtitle,
    required this.logoUrl,
    required this.onTap,
  });

  final String name;
  final String? subtitle;
  final String logoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              if (logoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    logoUrl,
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 28, height: 28),
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.iconCircleBackground(brightness),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.sports_soccer, size: 16),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(brightness)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.secondaryText(brightness)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Search tab -- team/player name search, separate from the Leagues tab's
// own competition search (different endpoint, different result shape).
// ─────────────────────────────────────────────────────────────────────────

enum _SearchKind { teams, players }

class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _service = FootballApiService();
  final _searchController = TextEditingController();
  _SearchKind _kind = _SearchKind.teams;
  Timer? _searchDebounce;
  Future<List<FootballTeam>>? _teamsFuture;
  Future<List<FootballPlayerProfile>>? _playersFuture;

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  void _runSearch(String query) {
    final q = query.trim();
    if (!mounted) return;
    setState(() {
      if (q.length < 3) {
        _teamsFuture = null;
        _playersFuture = null;
        return;
      }
      if (_kind == _SearchKind.teams) {
        _teamsFuture = _service.searchTeams(search: q);
        _playersFuture = null;
      } else {
        _playersFuture = _service.searchPlayers(search: q);
        _teamsFuture = null;
      }
    });
  }

  void _switchKind(_SearchKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    _runSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final season = currentFootballSeasonGuess();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Teams'),
                selected: _kind == _SearchKind.teams,
                onSelected: (_) => _switchKind(_SearchKind.teams),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Players'),
                selected: _kind == _SearchKind.players,
                onSelected: (_) => _switchKind(_SearchKind.players),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: _kind == _SearchKind.teams ? 'Search teams…' : 'Search players…',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (_kind == _SearchKind.teams)
          FutureBuilder<List<FootballTeam>>(
            future: _teamsFuture,
            builder: (context, snap) {
              if (_teamsFuture == null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'Type at least 3 characters to search for a team.',
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    UserFriendlyError.toMessage(snap.error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                );
              }
              final teams = snap.data ?? const [];
              if (teams.isEmpty) {
                return Center(
                  child: Text('No teams found.', style: TextStyle(color: AppTheme.secondaryText(brightness))),
                );
              }
              return Column(
                children: [
                  for (final t in teams)
                    _LeagueListTile(
                      name: t.name,
                      subtitle: t.countryName,
                      logoUrl: t.logoUrl,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FootballTeamScreen(
                            teamId: t.id,
                            teamName: t.name,
                            teamLogoUrl: t.logoUrl,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        else
          FutureBuilder<List<FootballPlayerProfile>>(
            future: _playersFuture,
            builder: (context, snap) {
              if (_playersFuture == null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'Type at least 3 characters to search for a player.',
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    UserFriendlyError.toMessage(snap.error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                );
              }
              final players = snap.data ?? const [];
              if (players.isEmpty) {
                return Center(
                  child: Text('No players found.', style: TextStyle(color: AppTheme.secondaryText(brightness))),
                );
              }
              return Column(
                children: [
                  for (final p in players)
                    _LeagueListTile(
                      name: p.name,
                      subtitle: p.nationality,
                      logoUrl: p.photoUrl,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FootballPlayerScreen(
                            playerId: p.id,
                            season: season,
                            fallbackName: p.name,
                            fallbackPhotoUrl: p.photoUrl,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
