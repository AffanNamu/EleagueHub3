// lib/features/organizer/presentation/organizer_workspace_gate_screen.dart
//
// OrganizerWorkspaceGateScreen — renders for the public `/org/:workspaceId`
// route (an organizer's Master League workspace).
//
// Wraps the existing MasterLeagueDetailsScreen so that:
//   - a deep-link "click" analytics event is recorded under the
//     'organizerWorkspace' entity type;
//   - a deleted/nonexistent workspace shows ContentUnavailableScreen
//     instead of the raw "Master League not found" empty state, matching
//     the rest of the sharing system's soft-landing behavior;
//   - this route works for signed-out web visitors, since
//     MasterLeagueDetailsScreen's visitor overview (follow / organizer
//     chat / view profile) already supports a null current user.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/analytics/link_analytics_service.dart';
import '../../../core/routing/route_resolver.dart';
import '../../../core/seo/web_meta_updater.dart';
import '../../../core/widgets/content_unavailable_screen.dart';
import '../../master_leagues/presentation/master_league_details_screen.dart';

class OrganizerWorkspaceGateScreen extends StatefulWidget {
  const OrganizerWorkspaceGateScreen({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  State<OrganizerWorkspaceGateScreen> createState() =>
      _OrganizerWorkspaceGateScreenState();
}

class _OrganizerWorkspaceGateScreenState
    extends State<OrganizerWorkspaceGateScreen> {
  late Future<bool> _existsFuture;

  @override
  void initState() {
    super.initState();
    _existsFuture = _checkExists();
  }

  Future<bool> _checkExists() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(widget.workspaceId.trim())
          .get()
          .timeout(const Duration(seconds: 12));
      if (snap.exists) {
        LinkAnalyticsService.instance.recordClick(
          entity: ShareableEntity(
            type: ShareableEntityType.organizerWorkspace,
            id: widget.workspaceId.trim(),
          ),
        );
        final data = snap.data() ?? const <String, dynamic>{};
        final name = (data['name'] as String? ?? '').trim();
        if (name.isNotEmpty) {
          WebMetaUpdater.applyEntityMeta(
            title: '$name | eSportlyic',
            description: (data['bio'] as String? ?? '').trim().isNotEmpty
                ? (data['bio'] as String).trim()
                : 'Check out $name\'s organizer workspace on eSportlyic.',
            imageUrl: (data['bannerUrl'] as String? ?? '').trim().isNotEmpty
                ? (data['bannerUrl'] as String).trim()
                : (data['logoUrl'] as String? ?? '').trim(),
          );
        }
      }
      return snap.exists;
    } catch (_) {
      // Fail open — let MasterLeagueDetailsScreen's own stream builder
      // handle transient read errors (it already distinguishes
      // permission-denied vs missing-doc vs loading).
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
            message: 'This organizer workspace is unavailable.',
          );
        }
        return MasterLeagueDetailsScreen(
          masterLeagueId: widget.workspaceId.trim(),
        );
      },
    );
  }
}
