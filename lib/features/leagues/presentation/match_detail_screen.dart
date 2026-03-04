import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/status_badge.dart';
import '../../highlights/data/highlights_repository_firebase.dart';
import '../../highlights/domain/match_highlight.dart';
import '../../highlights/logic/highlight_upload_controller.dart';
import '../../live/data/local_discovery.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/membership.dart';
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
  late final HighlightsRepositoryFirebase _highlightsRepo;
  late final Stream<List<MatchHighlight>> _highlightsStream;

  bool _busy = false;
  bool _loading = true;
  String? _loadError;

  String _status = 'Pending';

  FixtureMatch? _match;
  Map<String, Team> _teamsById = {};

  Membership? _membership;
  String? _myTeamId;
  bool _canUploadHighlight = false;

  String get _liveMatchId => widget.matchId;

  bool _matchFinishedForHighlights(FixtureMatch m) {
    // IMPORTANT:
    // FixtureMatch.isPlayed also requires scores.
    // For highlight eligibility, we consider the match finished when status is completed/played.
    return m.status == MatchStatus.completed || m.status == MatchStatus.played || m.isPlayed;
  }

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
    _highlightsRepo = HighlightsRepositoryFirebase();
    _highlightsStream = _highlightsRepo.watchHighlightsForMatch(widget.matchId);
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

      final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      final membershipFuture = uid.isEmpty
          ? Future<Membership?>.value(null)
          : _repo.getMembership(
              leagueId: widget.leagueId,
              userId: uid,
            );

      final results = await Future.wait([matchesFuture, teamsFuture, membershipFuture])
          .timeout(const Duration(seconds: 25));
      final matches = results[0] as List<FixtureMatch>;
      final teams = results[1] as List<Team>;
      final membership = results[2] as Membership?;

      FixtureMatch? m;
      for (final x in matches) {
        if (x.id == widget.matchId) {
          m = x;
          break;
        }
      }

      final myTeamIdRaw = (membership?.teamId ?? '').trim();
      final myTeamId = myTeamIdRaw.isEmpty ? null : myTeamIdRaw;

      final isFinished = (m != null) ? _matchFinishedForHighlights(m) : false;

      final canUpload = (m != null) &&
          isFinished &&
          (myTeamId != null) &&
          (myTeamId == m.homeTeamId.trim() || myTeamId == m.awayTeamId.trim());

      if (!mounted) return;
      setState(() {
        _match = m;
        _teamsById = {for (final t in teams) t.id: t};
        _status = (m != null && _matchFinishedForHighlights(m)) ? 'Completed' : 'Pending';
        _membership = membership;
        _myTeamId = myTeamId;
        _canUploadHighlight = canUpload;
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
    final ok = await ConnectivityService.instance
        .recheckConnection(timeout: const Duration(seconds: 4));
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

  Future<void> _openHighlightUrl(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null) {
      _showSnack('Invalid video URL.');
      return;
    }

    final ok = await launchUrl(
      u,
      mode: LaunchMode.externalApplication,
    );

    if (!ok) {
      _showSnack('Could not open video.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final isWide = MediaQuery.of(context).size.width > 600;

    final uploadState = ref.watch(highlightUploadControllerProvider);
    final uploadCtrl = ref.read(highlightUploadControllerProvider.notifier);

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
                          const SizedBox(height: 16),
                          _buildHighlightsSection(
                            context,
                            uploadState: uploadState,
                            onUploadTap: (_match == null)
                                ? null
                                : () async {
                                    final m = _match!;
                                    await uploadCtrl.uploadHighlightForMatch(m);
                                    if (!mounted) return;
                                    if (ref.read(highlightUploadControllerProvider).stage ==
                                        HighlightUploadStage.failed) {
                                      _showSnack(ref
                                          .read(highlightUploadControllerProvider)
                                          .message);
                                    }
                                  },
                            onOpenUrl: _openHighlightUrl,
                          ),
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
                _busy
                    ? l10n.tr('match_detail_opening').toUpperCase()
                    : l10n.tr('match_detail_open_host_live').toUpperCase(),
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

  Widget _buildHighlightsSection(
    BuildContext context, {
    required HighlightUploadState uploadState,
    required VoidCallback? onUploadTap,
    required Future<void> Function(String url) onOpenUrl,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final match = _match;
    final isFinished = match != null && _matchFinishedForHighlights(match);

    // STRICT UI VISIBILITY RULE:
    // - only visible if match finished AND membership.teamId is home/away.
    final showUpload = _canUploadHighlight && isFinished;

    final busy = uploadState.stage == HighlightUploadStage.compressing ||
        uploadState.stage == HighlightUploadStage.uploading ||
        uploadState.stage == HighlightUploadStage.preparingDoc ||
        uploadState.stage == HighlightUploadStage.probing ||
        uploadState.stage == HighlightUploadStage.picking ||
        uploadState.stage == HighlightUploadStage.finishing;

    String stageLabel() {
      switch (uploadState.stage) {
        case HighlightUploadStage.compressing:
          return 'Compressing…';
        case HighlightUploadStage.uploading:
          return 'Uploading…';
        case HighlightUploadStage.preparingDoc:
          return 'Preparing…';
        case HighlightUploadStage.probing:
          return 'Checking…';
        case HighlightUploadStage.picking:
          return 'Selecting…';
        case HighlightUploadStage.finishing:
          return 'Finalizing…';
        case HighlightUploadStage.done:
          return 'Uploaded';
        case HighlightUploadStage.failed:
          return 'Upload failed';
        case HighlightUploadStage.idle:
        default:
          return '';
      }
    }

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Highlights',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (showUpload)
                FilledButton.icon(
                  onPressed: busy ? null : onUploadTap,
                  icon: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : const Icon(Icons.upload, size: 18),
                  label: const Text(
                    'Upload',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (!isFinished)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.onSurface.withOpacity(0.12)),
              ),
              child: Text(
                'Highlights can be uploaded after the match is completed.',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else if (!showUpload)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.onSurface.withOpacity(0.12)),
              ),
              child: Text(
                'Only home/away team members can upload highlights.',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          if (showUpload && uploadState.stage != HighlightUploadStage.idle) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.onSurface.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stageLabel(),
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        if (uploadState.message.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            uploadState.message.trim(),
                            style: TextStyle(
                              color: uploadState.stage == HighlightUploadStage.failed
                                  ? cs.error
                                  : cs.onSurface.withOpacity(0.70),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: (uploadState.progress01 <= 0 || uploadState.progress01 > 1)
                              ? null
                              : uploadState.progress01,
                          strokeWidth: 4,
                          color: uploadState.stage == HighlightUploadStage.failed ? cs.error : cs.primary,
                          backgroundColor: cs.onSurface.withOpacity(0.08),
                        ),
                        Center(
                          child: Text(
                            uploadState.progress01 <= 0
                                ? ''
                                : '${(uploadState.progress01 * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          StreamBuilder<List<MatchHighlight>>(
            stream: _highlightsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary),
                    ),
                  ),
                );
              }

              final items = snap.data ?? const <MatchHighlight>[];
              if (items.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                  ),
                  child: Text(
                    'No highlights yet.',
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return Column(
                children: [
                  for (final h in items) ...[
                    _HighlightCard(
                      highlight: h,
                      teamName: _teamsById[h.teamId]?.name ?? 'Team',
                      isMine: (h.uploadedBy.trim().isNotEmpty) &&
                          (h.uploadedBy.trim() ==
                              (FirebaseAuth.instance.currentUser?.uid ?? '').trim()),
                      onOpen: h.secureUrl.trim().isEmpty ? null : () => onOpenUrl(h.secureUrl),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.teamName,
    required this.isMine,
    required this.onOpen,
  });

  final MatchHighlight highlight;
  final String teamName;
  final bool isMine;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final status = highlight.status;
    final hasUrl = highlight.secureUrl.trim().isNotEmpty;

    Color statusColor() {
      if (status == MatchHighlight.statusApproved) return cs.primary;
      if (status == MatchHighlight.statusProcessing) return const Color(0xFFF59E0B);
      return cs.onSurface.withOpacity(0.55);
    }

    String statusLabel() {
      if (status == MatchHighlight.statusApproved) return 'APPROVED';
      if (status == MatchHighlight.statusProcessing) return 'PROCESSING';
      return 'UPLOADING';
    }

    return InkWell(
      onTap: hasUrl ? onOpen : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.onSurface.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            _Thumb(url: highlight.thumbnailUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teamName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor().withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: statusColor().withOpacity(0.22)),
                        ),
                        child: Text(
                          statusLabel(),
                          style: TextStyle(
                            color: statusColor(),
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Yours',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hasUrl) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Tap to play',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(
                      'Video will appear when upload finishes.',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              hasUrl ? Icons.play_circle_fill : Icons.cloud_upload_outlined,
              color: hasUrl ? cs.primary : cs.onSurface.withOpacity(0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = url.trim();

    return Container(
      width: 64,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.onSurface.withOpacity(0.06),
        border: Border.all(color: cs.onSurface.withOpacity(0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: u.isEmpty
          ? Center(
              child: Icon(Icons.video_file_outlined, color: cs.onSurface.withOpacity(0.55), size: 18),
            )
          : Image.network(
              u,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.video_file_outlined, color: cs.onSurface.withOpacity(0.55), size: 18),
              ),
              loadingBuilder: (context, child, event) {
                if (event == null) return child;
                return Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary.withOpacity(0.85)),
                  ),
                );
              },
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
                errorBuilder: (_, __, ___) => Icon(
                  Icons.emoji_events_outlined,
                  size: 14,
                  color: cs.onSurface.withOpacity(0.55),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: 14,
                    color: cs.onSurface.withOpacity(0.55),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: 14,
                color: cs.onSurface.withOpacity(0.55),
              ),
      ),
    );
  }
}
