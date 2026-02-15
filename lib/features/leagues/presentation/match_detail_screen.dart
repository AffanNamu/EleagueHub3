import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
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
  bool _loading = true;
  String? _loadError;

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

  String _homeImageUrl() {
    final m = _match;
    if (m == null) return '';
    return (_teamsById[m.homeTeamId]?.teamImageUrl ?? '').trim();
  }

  String _awayImageUrl() {
    final m = _match;
    if (m == null) return '';
    return (_teamsById[m.awayTeamId]?.teamImageUrl ?? '').trim();
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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final matchesFuture = _repo.getMatches(widget.leagueId);
      final teamsFuture = _repo.getTeams(widget.leagueId);

      final results = await Future.wait([matchesFuture, teamsFuture]).timeout(const Duration(seconds: 25));
      final matches = results[0] as List<FixtureMatch>;
      final teams = results[1] as List<Team>;

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
        _status = (m?.isPlayed ?? false) ? 'Completed' : 'Pending';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = UserFriendlyError.toMessage(e);
        _loading = false;
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyLiveId() async {
    final l10n = context.l10n;

    await Clipboard.setData(ClipboardData(text: _liveMatchId));
    if (!mounted) return;
    _showSnack('${l10n.tr('match_detail_live_id_copied_prefix')}$_liveMatchId');
  }

  Future<bool> _ensureSignedInAndOnline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      _showSnack('Please sign in and try again.');
      if (mounted) context.go('/login');
      return false;
    }

    await ConnectivityService.instance.initialize();
    final ok = await ConnectivityService.instance.recheckConnection(timeout: const Duration(seconds: 4));
    if (!ok) {
      _showSnack(UserFriendlyError.toMessage(SocketException('offline')));
      return false;
    }

    return true;
  }

  Future<void> _openLive() async {
    if (_busy) return;

    final l10n = context.l10n;

    final ok = await _ensureSignedInAndOnline();
    if (!ok) return;
    if (!mounted) return;

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

    setState(() => _busy = true);
    try {
      const port = 8765;

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
    } catch (e) {
      _showSnack(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('match_detail_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            onPressed: _loading ? null : _loadMatch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 700 : 500),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : (_loadError != null)
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Glass(
                          padding: const EdgeInsets.all(16),
                          borderRadius: 20,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _loadMatch,
                                  icon: const Icon(Icons.refresh),
                                  label: Text(l10n.tr('common_retry')),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () => Navigator.maybePop(context),
                                child: Text(l10n.tr('common_back')),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
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

    final homeName = _homeName(context);
    final awayName = _awayName(context);

    final homeUrl = _homeImageUrl();
    final awayUrl = _awayImageUrl();

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _TeamThumb(url: homeUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    homeName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.tr('match_detail_vs'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.40),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    awayName,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                _TeamThumb(url: awayUrl),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
              onPressed: _busy ? null : _openLive,
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

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({
    required this.url,
  });

  final String url;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url, {int width = 64, int height = 64}) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary = u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;

    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = 'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly = first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 64,
                cacheHeight: 64,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55)),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55));
                },
              )
            : Icon(Icons.emoji_events_outlined, size: 14, color: cs.onSurface.withOpacity(0.55)),
      ),
    );
  }
}
