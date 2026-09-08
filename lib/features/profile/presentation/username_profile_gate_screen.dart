// lib/features/profile/presentation/username_profile_gate_screen.dart
//
// UsernameProfileGateScreen — renders for the public `/u/:username` route.
//
// Responsibilities:
//   1. Resolve the username -> userId via UserProfileRepository (which
//      itself reads the `usernames/{lower}` reservation collection).
//   2. Record a deep-link "click" analytics event.
//   3. Render the existing PublicTeamProfileScreen for that userId, or
//      ContentUnavailableScreen if the username doesn't resolve.
//
// This screen intentionally does NOT redirect/replace the URL to
// `/profile/:userId` — keeping `/u/:username` as the browser URL means the
// canonical share link a visitor sees/copies from their address bar is
// always the pretty username form, and refreshing the page keeps working
// without a redirect round-trip.
import 'package:flutter/material.dart';

import '../../../core/analytics/link_analytics_service.dart';
import '../../../core/routing/route_resolver.dart';
import '../../../core/seo/web_meta_updater.dart';
import '../../../core/widgets/content_unavailable_screen.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import 'public_team_profile_screen.dart';

class UsernameProfileGateScreen extends StatefulWidget {
  const UsernameProfileGateScreen({super.key, required this.username});

  final String username;

  @override
  State<UsernameProfileGateScreen> createState() =>
      _UsernameProfileGateScreenState();
}

class _UsernameProfileGateScreenState
    extends State<UsernameProfileGateScreen> {
  final UserProfileRepository _repo = UserProfileRepository();

  late Future<UserProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<UserProfile?> _resolve() async {
    try {
      final profile = await _repo.fetchByUsername(widget.username);
      if (profile != null) {
        LinkAnalyticsService.instance.recordClick(
          entity: ShareableEntity(
            type: ShareableEntityType.userProfile,
            username: widget.username.trim().toLowerCase(),
          ),
        );
        WebMetaUpdater.applyEntityMeta(
          title: '${profile.displayName} | eSportlyic',
          description: 'Check out ${profile.displayName}\'s profile on eSportlyic.',
          imageUrl: profile.effectivePhotoUrl,
        );
      }
      return profile;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    WebMetaUpdater.resetToDefault();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UsernameProfileGateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username.trim().toLowerCase() !=
        widget.username.trim().toLowerCase()) {
      setState(() => _future = _resolve());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snap.data;
        if (profile == null) {
          return const ContentUnavailableScreen(
            message: 'This profile is unavailable.',
            subtitle:
                'The username may be misspelled, or this account no longer exists.',
          );
        }

        return PublicTeamProfileScreen(userId: profile.userId);
      },
    );
  }
}
