import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
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

  // Keep as a stable status code (do not localize this string directly).
  // If we need localized rendering, we should update StatusBadge to map codes -> l10n.
  String _status = 'Pending';

  FixtureMatch? _match;
  Map<String, Team> _teamsById = {};

  String get _liveMatchId => widget.matchId;

  String _homeName(BuildContext context) {
    final l10n = context.l10n;
    final m = _match;
    if (m == null) return l10n.tr('admin_score_home_fallback');
    return _teamsById[m.homeTeamId]?.name ?? l10n.tr('admin_score_home_fallback');
  }

  String _awayName(BuildContext context) {
    final l10n = context.l10n;
    final m = _match;
    if (m == null) return l10n.tr('admin_score_away_fallback');
    return _teamsById[m.awayTeamId]?.name ?? l10n.tr('admin_score_away_fallback');
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
    final l10n = context.l10n;

    await Clipboard.setData(ClipboardData(text: _liveMatchId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.tr('match_detail_live_id_copied_prefix')}$_liveMatchId'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startLocalLive() async {
    if (_busy) return;

    final l10n = context.l10n;

    final side = await showModalBottomSheet<LiveHostSide>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            borderRadius: 20,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.tr('match_detail_streaming_as_title'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, LiveHostSide.home),
                        child: Text(_homeName(ctx)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, LiveHostSide.away),
                        child: Text(_awayName(ctx)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, LiveHostSide.unknown),
                  child: Text(l10n.tr('match_detail_not_sure_spectator')),
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
          'homeName': _homeName(context),
          'awayName': _awayName(context),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('match_detail_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 700 : 500),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_homeName(context)}  ${l10n.tr('match_detail_vs')}  ${_awayName(context)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('match_detail_live_section_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr('match_detail_live_section_description'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.55),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.tag, size: 18, color: cs.onSurface.withOpacity(0.60)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _liveMatchId,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.tr('match_detail_copy_live_match_id_tooltip'),
                onPressed: _copyLiveId,
                icon: Icon(Icons.copy, size: 18, color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _startLocalLive,
              icon: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.play_circle_fill),
              label: Text(
                _busy ? l10n.tr('match_detail_opening').toUpperCase() : l10n.tr('match_detail_open_host_live').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tr('match_detail_tip_text'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.45),
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
