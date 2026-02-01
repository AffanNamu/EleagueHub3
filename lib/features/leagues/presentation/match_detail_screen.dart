import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/status_badge.dart';
import '../../live/data/local_discovery.dart';
import '../data/leagues_repository_local.dart';
import '../models/fixture_match.dart';
import '../models/team.dart';

class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.leagueId,
    required this.matchId,
  });

  final String leagueId;
  final String matchId;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  late final LocalLeaguesRepository _repo;

  bool _busy = false;
  String _status = 'Pending';

  FixtureMatch? _match;
  Map<String, Team> _teamsById = {};

  String get _liveMatchId => widget.matchId;

  String get _homeName {
    final m = _match;
    if (m == null) return 'Home';
    return _teamsById[m.homeTeamId]?.name ?? 'Home';
  }

  String get _awayName {
    final m = _match;
    if (m == null) return 'Away';
    return _teamsById[m.awayTeamId]?.name ?? 'Away';
  }

  int get _homeScore => _match?.homeScore ?? 0;
  int get _awayScore => _match?.awayScore ?? 0;

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadMatch();
  }

  Future<void> _loadMatch() async {
    try {
      final matches = await _repo.getMatches(widget.leagueId);
      final teams = await _repo.getTeams(widget.leagueId);

      FixtureMatch? m;
      for (final x in matches) {
        if (x.id == widget.matchId) {
          m = x;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _match = m;
        _teamsById = {for (final t in teams) t.id: t};
      });
    } catch (_) {
      // fallback (keep prior state)
    }
  }

  Future<void> _copyLiveId() async {
    await Clipboard.setData(ClipboardData(text: _liveMatchId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Live Match ID copied: $_liveMatchId'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startLocalLive() async {
    if (_busy) return;

    final side = await showModalBottomSheet<LiveHostSide>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            borderRadius: 20,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'You are streaming as:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, LiveHostSide.home),
                        child: Text(_homeName),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, LiveHostSide.away),
                        child: Text(_awayName),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, LiveHostSide.unknown),
                  child: const Text('Not sure / Spectator'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    const port = 8765;

    setState(() => _busy = true);
    try {
      await context.push(
        '/live/view/$_liveMatchId',
        extra: {
          'isHost': true,
          'port': port,
          'homeName': _homeName,
          'awayName': _awayName,
          'homeScore': _homeScore,
          'awayScore': _awayScore,
          'side': (side == null) ? 'unknown' : liveHostSideToWire(side),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Match Details'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 700 : 500),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _buildLiveSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$_homeName  vs  $_awayName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StatusBadge(_status),
        ],
      ),
    );
  }

  Widget _buildLiveSection(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Match (Gamers Mode)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Stream your screen + front camera. Viewers will see both players cams (top-left/top-right) '
            'and one player’s screen (main).',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.tag, size: 18, color: Colors.white60),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _liveMatchId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy Live Match ID',
                onPressed: _copyLiveId,
                icon: const Icon(Icons.copy, size: 18, color: Colors.cyanAccent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _startLocalLive,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.play_circle_fill),
              label: Text(
                _busy ? 'OPENING...' : 'OPEN HOST LIVE',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tip: Both players can host using the same Match ID.\n'
            'Viewers on the same Wi‑Fi/hotspot can join via Auto‑Discovery.',
            style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}
