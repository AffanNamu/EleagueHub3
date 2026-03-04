import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../leagues/models/fixture_match.dart';
import '../../leagues/models/team.dart';
import '../domain/match_highlight.dart';

/// League highlights preview section intended for LeagueDetailScreen.
///
/// Ultra-low-cost UI strategy:
/// - Keep list small (<= 10).
/// - Use lightweight thumbnails only (small width).
/// - Open video externally (no in-app player package).
class LeagueHighlightsSection extends StatelessWidget {
  const LeagueHighlightsSection({
    super.key,
    required this.leagueId,
    required this.highlightsStream,
    required this.matchesById,
    required this.teamsById,
    this.limitLabel = 'Latest highlights',
  });

  final String leagueId;
  final Stream<List<MatchHighlight>> highlightsStream;
  final Map<String, FixtureMatch> matchesById;
  final Map<String, Team> teamsById;
  final String limitLabel;

  Future<void> _openVideo(BuildContext context, String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null) {
      _snack(context, 'Invalid video URL.');
      return;
    }

    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok) _snack(context, 'Could not open video.');
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  String _matchLabel(FixtureMatch? m) {
    if (m == null) return 'Match';
    final h = teamsById[m.homeTeamId]?.name.trim().isNotEmpty == true ? teamsById[m.homeTeamId]!.name.trim() : 'Home';
    final a = teamsById[m.awayTeamId]?.name.trim().isNotEmpty == true ? teamsById[m.awayTeamId]!.name.trim() : 'Away';
    return '$h vs $a';
  }

  String _uploaderTeamName(MatchHighlight h) {
    final t = teamsById[h.teamId]?.name.trim() ?? '';
    return t.isNotEmpty ? t : 'Team';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  limitLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                'Open to watch',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.55),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<MatchHighlight>>(
            stream: highlightsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
                    _LeagueHighlightTile(
                      highlight: h,
                      matchLabel: _matchLabel(matchesById[h.matchId]),
                      uploaderTeamName: _uploaderTeamName(h),
                      onOpenVideo: h.secureUrl.trim().isEmpty ? null : () => _openVideo(context, h.secureUrl),
                      onOpenMatch: () {
                        final matchId = h.matchId.trim();
                        if (matchId.isEmpty) return;
                        context.push('/leagues/$leagueId/matches/$matchId');
                      },
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

class _LeagueHighlightTile extends StatelessWidget {
  const _LeagueHighlightTile({
    required this.highlight,
    required this.matchLabel,
    required this.uploaderTeamName,
    required this.onOpenVideo,
    required this.onOpenMatch,
  });

  final MatchHighlight highlight;
  final String matchLabel;
  final String uploaderTeamName;
  final VoidCallback? onOpenVideo;
  final VoidCallback onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasUrl = highlight.secureUrl.trim().isNotEmpty;

    Color statusColor() {
      if (highlight.status == MatchHighlight.statusApproved) return cs.primary;
      if (highlight.status == MatchHighlight.statusProcessing) return const Color(0xFFF59E0B);
      return cs.onSurface.withOpacity(0.55);
    }

    String statusLabel() {
      if (highlight.status == MatchHighlight.statusApproved) return 'APPROVED';
      if (highlight.status == MatchHighlight.statusProcessing) return 'PROCESSING';
      return 'UPLOADING';
    }

    return InkWell(
      onTap: hasUrl ? onOpenVideo : null,
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
                    matchLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          uploaderTeamName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onOpenMatch,
                        icon: const Icon(Icons.sports_soccer, size: 16),
                        label: const Text(
                          'Match',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (hasUrl)
                        FilledButton.tonalIcon(
                          onPressed: onOpenVideo,
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text(
                            'Watch',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        )
                      else
                        Text(
                          'Not ready yet',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
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
