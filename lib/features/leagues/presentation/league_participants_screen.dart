import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../models/membership.dart';
import '../models/team.dart';

class LeagueParticipantsScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const LeagueParticipantsScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueParticipantsScreen> createState() => _LeagueParticipantsScreenState();
}

class _LeagueParticipantsScreenState extends ConsumerState<LeagueParticipantsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserProfileRepository _profiles = UserProfileRepository();

  bool _loading = true;
  Object? _error;

  List<Membership> _memberships = [];
  Map<String, Team> _teamsById = {};

  /// userId -> teamName (from users/{userId})
  Map<String, String> _teamNameByUserId = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String _friendlyMessageForError(Object error) {
    if (error is SocketException) {
      return 'Your network appears to be offline. Please check your connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Your internet connection seems unstable. Please try again.';
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Your network appears to be offline. Please check your connection and try again.';
        case 'permission-denied':
          return 'You don’t have access to this league.';
        case 'unauthenticated':
          return 'Please sign in and try again.';
        default:
          return "We couldn't load participants right now. Please try again.";
      }
    }

    return 'Something went wrong. Please try again.';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        throw const FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated');
      }

      final membershipsSnap = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('memberships')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final teamsSnap = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final memberships = membershipsSnap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? widget.leagueId;

        map['role'] = (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
        map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        map['version'] = (map['version'] as num?)?.toInt() ?? 1;

        return Membership.fromRemoteMap(map);
      }).toList(growable: false);

      final teams = teamsSnap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? widget.leagueId;
        return Team.fromRemoteMap(map);
      }).toList(growable: false);

      final leagueMembers = memberships.where((m) => m.leagueId == widget.leagueId).toList(growable: false);

      final uniqueUserIds = leagueMembers.map((m) => m.userId).where((id) => id.trim().isNotEmpty).toSet().toList();

      final Map<String, String> resolved = {};
      await Future.wait(
        uniqueUserIds.map((userId) async {
          try {
            final p = await _profiles.fetchByUserId(userId).timeout(const Duration(seconds: 10));
            if (p != null && p.teamName.trim().isNotEmpty) {
              resolved[userId] = p.teamName.trim();
            }
          } catch (_) {
            // Best-effort only.
          }
        }),
      );

      if (!mounted) return;
      setState(() {
        _memberships = leagueMembers;
        _teamsById = {for (final t in teams) t.id: t};
        _teamNameByUserId = resolved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      _showSnack(_friendlyMessageForError(e is Object ? e : Exception('unknown')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_participants_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : (_error != null ? _buildErrorState() : _buildBody()),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Glass(
        borderRadius: 24,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                'Couldn’t load participants',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Please check your network and try again.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_memberships.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Glass(
          borderRadius: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 40, color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('league_participants_empty_title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.tr('league_participants_empty_subtitle'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final organizers = _memberships.where((m) => m.role == LeagueRole.organizer).toList(growable: false);
    final members = _memberships.where((m) => m.role == LeagueRole.member).toList(growable: false);

    final onBg = cs.onBackground;

    final sectionTitleStyle = TextStyle(
      color: onBg.withOpacity(0.78),
      fontWeight: FontWeight.w900,
      fontSize: 13,
      letterSpacing: 0.2,
    );

    return RefreshIndicator(
      onRefresh: _load,
      color: cs.primary,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
        children: [
          if (organizers.isNotEmpty) ...[
            Text(l10n.tr('league_participants_organizers_title'), style: sectionTitleStyle),
            const SizedBox(height: 8),
            ...organizers.map(_buildMembershipTile),
            const SizedBox(height: 16),
          ],
          Text(l10n.tr('league_participants_participants_title'), style: sectionTitleStyle),
          const SizedBox(height: 8),
          ...members.map(_buildMembershipTile),
        ],
      ),
    );
  }

  Widget _buildMembershipTile(Membership m) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final assignedLeagueTeamName = (m.teamId != null && m.teamId!.isNotEmpty)
        ? (_teamsById[m.teamId!]?.name ?? '${l10n.tr('league_participants_team_prefix')}${m.teamId}')
        : l10n.tr('league_participants_no_team');

    final globalTeamName = _teamNameByUserId[m.userId];
    final title = (globalTeamName != null && globalTeamName.trim().isNotEmpty) ? globalTeamName : m.userId;

    final isOrganizer = m.role == LeagueRole.organizer;

    final subtitle = isOrganizer
        ? '${l10n.tr('league_participants_role_organizer')} • $assignedLeagueTeamName • ${l10n.tr('league_participants_userid_prefix')}${m.userId}'
        : '$assignedLeagueTeamName • ${l10n.tr('league_participants_userid_prefix')}${m.userId}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        borderRadius: 18,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isOrganizer ? cs.primary.withOpacity(0.18) : cs.onSurface.withOpacity(0.08),
            child: Icon(
              isOrganizer ? Icons.verified_user : Icons.person,
              color: isOrganizer ? cs.primary : cs.onSurface.withOpacity(0.72),
              size: 18,
            ),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.65),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
