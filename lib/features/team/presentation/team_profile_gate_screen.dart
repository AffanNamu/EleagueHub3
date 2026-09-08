// lib/features/team/presentation/team_profile_gate_screen.dart
//
// TeamProfileGateScreen — renders for the public `/team/:teamId` route.
//
// eSportlyic does not model a "team" as an aggregate separate from a
// user's team/squad profile (see TeamProfileRepository, which is always
// keyed by userId — there is no standalone `teams/{teamId}` collection).
// A team's public share link therefore addresses the SAME underlying
// profile screen as `/u/{username}` and `/profile/{userId}`, using the
// owning user's id as the "team id".
//
// This wrapper exists (rather than aliasing the route directly to
// PublicTeamProfileScreen) so that:
//   - deep-link analytics are recorded under the 'team' entity type,
//     distinct from 'userProfile' clicks, for accurate share analytics;
//   - a future dedicated Team aggregate can be introduced by changing
//     ONLY this file plus RouteResolver, with zero churn to callers.
import 'package:flutter/material.dart';

import '../../../core/analytics/link_analytics_service.dart';
import '../../../core/routing/route_resolver.dart';
import '../../../core/seo/web_meta_updater.dart';
import '../../../core/widgets/content_unavailable_screen.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../profile/presentation/public_team_profile_screen.dart';

class TeamProfileGateScreen extends StatefulWidget {
  const TeamProfileGateScreen({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamProfileGateScreen> createState() => _TeamProfileGateScreenState();
}

class _TeamProfileGateScreenState extends State<TeamProfileGateScreen> {
  late Future<bool> _existsFuture;

  @override
  void initState() {
    super.initState();
    _existsFuture = _checkExists();
  }

  Future<bool> _checkExists() async {
    try {
      final repo = UserProfileRepository();
      final exists = await repo.profileExists(widget.teamId);
      if (exists) {
        LinkAnalyticsService.instance.recordClick(
          entity: ShareableEntity(
            type: ShareableEntityType.team,
            id: widget.teamId.trim(),
          ),
        );
        try {
          final profile = await repo.fetchByUserId(widget.teamId);
          if (profile != null) {
            WebMetaUpdater.applyEntityMeta(
              title: '${profile.displayName} | eSportlyic',
              description:
                  'Check out ${profile.displayName}\'s team on eSportlyic.',
              imageUrl: profile.effectivePhotoUrl,
            );
          }
        } catch (_) {}
      }
      return exists;
    } catch (_) {
      return false;
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
            message: 'This team profile is unavailable.',
          );
        }
        return PublicTeamProfileScreen(userId: widget.teamId);
      },
    );
  }
}
