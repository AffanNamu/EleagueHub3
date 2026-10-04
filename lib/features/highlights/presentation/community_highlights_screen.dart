// lib/features/highlights/presentation/community_highlights_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/highlights_feed_repository_firebase.dart';
import '../domain/match_highlight.dart';
import 'highlight_player_screen.dart';

/// Community-wide "browse all highlights" screen -- the capability the
/// Community screen's Highlights row was a "Soon" placeholder for.
/// Unlike LeagueHighlightsSection (embedded per-league, with pre-loaded
/// match/team maps to resolve names), this is a standalone screen fed by
/// HighlightsFeedRepositoryFirebase.watchAllHighlights(), a collectionGroup
/// query across every league the signed-in user can read -- so there's no
/// single league's team roster to resolve names against here; cards show
/// the uploading team id's/league id's tail and link to the match itself.
class CommunityHighlightsScreen extends StatefulWidget {
  const CommunityHighlightsScreen({super.key});

  @override
  State<CommunityHighlightsScreen> createState() => _CommunityHighlightsScreenState();
}

class _CommunityHighlightsScreenState extends State<CommunityHighlightsScreen> {
  final _repo = HighlightsFeedRepositoryFirebase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Highlights')),
      body: StreamBuilder<List<MatchHighlight>>(
        stream: _repo.watchAllHighlights(limit: 30),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <MatchHighlight>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No highlights yet. Uploaded match clips from leagues you\'re in will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _HighlightCard(highlight: items[i]),
          );
        },
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight});

  final MatchHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasUrl = highlight.secureUrl.trim().isNotEmpty;
    final thumb = highlight.thumbnailUrl.trim();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: hasUrl
          ? () => openHighlightPlayer(context, videoUrl: highlight.secureUrl)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.onSurface.withOpacity(0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb.isNotEmpty)
                    Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: cs.onSurface.withOpacity(0.08)),
                    )
                  else
                    Container(color: cs.onSurface.withOpacity(0.08)),
                  if (hasUrl)
                    Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 36,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        final leagueId = highlight.leagueId.trim();
                        final matchId = highlight.matchId.trim();
                        if (leagueId.isEmpty || matchId.isEmpty) return;
                        context.push('/leagues/$leagueId/matches/$matchId');
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.sports_soccer, size: 14),
                      label: const Text(
                        'View match',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                      ),
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
