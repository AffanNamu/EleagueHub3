// lib/features/leagues/presentation/competition_gate_screen.dart
//
// CompetitionGateScreen — renders for the public `/competition/:id` route.
//
// Competitions are modeled internally as "leagues" (LeagueDetailScreen,
// `/leagues/:id`). The public share surface intentionally uses the
// clearer "competition" wording and its own top-level route so the URL a
// visitor sees and shares always reads `/competition/{id}` — this wrapper
// is what makes that possible without duplicating LeagueDetailScreen.
//
// Also responsible for:
//   - recording a deep-link "click" analytics event under the
//     'competition' entity type;
//   - showing ContentUnavailableScreen for a deleted/nonexistent
//     competition instead of leaking a raw Firestore error.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/analytics/link_analytics_service.dart';
import '../../../core/routing/route_resolver.dart';
import '../../../core/seo/web_meta_updater.dart';
import '../../../core/widgets/content_unavailable_screen.dart';
import 'league_detail_screen.dart';

class CompetitionGateScreen extends StatefulWidget {
  const CompetitionGateScreen({super.key, required this.competitionId});

  final String competitionId;

  @override
  State<CompetitionGateScreen> createState() => _CompetitionGateScreenState();
}

class _CompetitionGateScreenState extends State<CompetitionGateScreen> {
  late Future<bool> _existsFuture;

  @override
  void initState() {
    super.initState();
    _existsFuture = _checkExists();
  }

  Future<bool> _checkExists() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.competitionId.trim())
          .get()
          .timeout(const Duration(seconds: 12));
      if (snap.exists) {
        LinkAnalyticsService.instance.recordClick(
          entity: ShareableEntity(
            type: ShareableEntityType.competition,
            id: widget.competitionId.trim(),
          ),
        );
        final data = snap.data() ?? const <String, dynamic>{};
        final name = (data['name'] as String? ?? '').trim();
        if (name.isNotEmpty) {
          WebMetaUpdater.applyEntityMeta(
            title: '$name | eSportlyic',
            description: 'Join $name on eSportlyic.',
            imageUrl: (data['leagueImageUrl'] as String? ?? '').trim(),
          );
        }
      }
      return snap.exists;
    } catch (_) {
      // Fail open — canReadLeagueDirect() security-rules privacy checks
      // still apply when LeagueDetailScreen itself reads the document.
      return true;
    }
  }

  @override
  void dispose() {
    WebMetaUpdater.resetToDefault();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _existsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return const ContentUnavailableScreen(
            message: 'This competition is unavailable.',
          );
        }
        return LeagueDetailScreen(leagueId: widget.competitionId.trim());
      },
    );
  }
}
