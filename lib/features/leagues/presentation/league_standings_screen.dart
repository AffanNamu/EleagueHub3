import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/standings/standings.dart';
import '../models/league_format.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

class LeagueStandingsScreen extends ConsumerStatefulWidget {
  final String id;

  const LeagueStandingsScreen({
    super.key,
    required this.id,
  });

  @override
  ConsumerState<LeagueStandingsScreen> createState() => _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState extends ConsumerState<LeagueStandingsScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();

    // Auto-sync when opening standings (participant will pull latest matches)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncAndRefresh();
    });
  }

  Future<void> _syncAndRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    await SyncTrigger.trySync();

    // Recompute providers from local storage after pull
    ref.invalidate(leagueProvider(widget.id));
    ref.invalidate(leagueStandingsProvider(widget.id));
    ref.invalidate(leagueGroupedStandingsProvider(widget.id));

    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final leagueAsync = ref.watch(leagueProvider(widget.id));

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Standings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _syncAndRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _syncAndRefresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('League Standings'),
                      const SizedBox(height: 12),
                      Expanded(
                        child: leagueAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(color: Colors.cyanAccent),
                          ),
                          error: (error, stack) => Center(
                            child: Text(
                              'Failed to load league.\n${error.toString()}',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          data: (league) {
                            switch (league.format) {
                              case LeagueFormat.uclGroup:
                                final groupedAsync = ref.watch(
                                  leagueGroupedStandingsProvider(widget.id),
                                );
                                return groupedAsync.when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      'Failed to load group standings.\n${error.toString()}',
                                      style: const TextStyle(color: Colors.white70),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (groupMap) {
                                    if (groupMap.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'No group results yet.\n'
                                          'Standings will appear after group matches are played.',
                                          style: TextStyle(color: Colors.white54),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }

                                    final groupKeys = groupMap.keys.toList()..sort();

                                    return ListView.builder(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      itemCount: groupKeys.length,
                                      itemBuilder: (context, index) {
                                        final groupId = groupKeys[index];
                                        final rows = groupMap[groupId] ?? const <StandingsRow>[];

                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom: index == groupKeys.length - 1 ? 0 : 16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Text(
                                                  groupId,
                                                  style: const TextStyle(
                                                    color: Colors.cyanAccent,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              StandingsTable(rows: rows),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );

                              case LeagueFormat.uclSwiss:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      'Failed to load standings.\n${error.toString()}',
                                      style: const TextStyle(color: Colors.white70),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (rows) {
                                    return FutureBuilder<int>(
                                      future: _getSwissCurrentRound(ref, widget.id),
                                      builder: (context, snapshot) {
                                        final current = snapshot.data ?? 0;
                                        final total = league.settings.swissRounds;

                                        final label = current == 0
                                            ? 'Swiss phase: no rounds yet (max $total rounds)'
                                            : 'Swiss phase: Round $current of $total';

                                        final autoColor = Colors.green.withOpacity(0.12);
                                        final playoffColor = Theme.of(context).colorScheme.primary.withOpacity(0.10);
                                        final eliminatedColor = Colors.red.withOpacity(0.08);

                                        if (rows.isEmpty) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                              const SizedBox(height: 8),
                                              _swissLegend(
                                                autoColor: autoColor,
                                                playoffColor: playoffColor,
                                                eliminatedColor: eliminatedColor,
                                              ),
                                              const SizedBox(height: 12),
                                              const Expanded(
                                                child: Center(
                                                  child: Text(
                                                    'No results yet.\n'
                                                    'Standings will appear here after matches are played.',
                                                    style: TextStyle(color: Colors.white54),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                            const SizedBox(height: 8),
                                            _swissLegend(
                                              autoColor: autoColor,
                                              playoffColor: playoffColor,
                                              eliminatedColor: eliminatedColor,
                                            ),
                                            const SizedBox(height: 8),
                                            Expanded(
                                              child: StandingsTable(
                                                rows: rows,
                                                rowColorBuilder: (ctx, index, row, totalRows) {
                                                  final rank = index + 1;
                                                  if (rank <= 8) return autoColor;
                                                  if (rank <= 24) return playoffColor;
                                                  return eliminatedColor;
                                                },
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );

                              case LeagueFormat.classic:
                              default:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      'Failed to load standings.\n${error.toString()}',
                                      style: const TextStyle(color: Colors.white70),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (rows) {
                                    if (rows.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'No results yet.\n'
                                          'Standings will appear here after matches are played.',
                                          style: TextStyle(color: Colors.white54),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    return StandingsTable(rows: rows);
                                  },
                                );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<int> _getSwissCurrentRound(WidgetRef ref, String leagueId) async {
  final repo = ref.read(localLeaguesRepositoryProvider);
  final allMatches = await repo.getMatches(leagueId);
  if (allMatches.isEmpty) return 0;
  return allMatches.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
}

Widget _swissLegend({
  required Color autoColor,
  required Color playoffColor,
  required Color eliminatedColor,
}) {
  Widget dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
      );

  const labelStyle = TextStyle(color: Colors.white54, fontSize: 11);

  return Row(
    children: [
      dot(autoColor),
      const SizedBox(width: 6),
      const Text('Top 8: Round of 16', style: labelStyle),
      const SizedBox(width: 12),
      dot(playoffColor),
      const SizedBox(width: 6),
      const Text('9–24: Play-off', style: labelStyle),
      const SizedBox(width: 12),
      dot(eliminatedColor),
      const SizedBox(width: 6),
      const Text('25+: Eliminated', style: labelStyle),
    ],
  );
}
