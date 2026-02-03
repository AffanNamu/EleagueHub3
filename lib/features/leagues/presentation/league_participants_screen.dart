import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../data/leagues_repository_local.dart';
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
  late LocalLeaguesRepository _repo;
  final UserProfileRepository _profiles = UserProfileRepository();

  bool _loading = true;
  List<Membership> _memberships = [];
  Map<String, Team> _teamsById = {};

  /// userId -> teamName (from users/{userId})
  Map<String, String> _teamNameByUserId = {};

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _load();
  }

  Future<void> _load() async {
    final allMemberships = await _repo.listMemberships();
    final leagueMembers = allMemberships.where((m) => m.leagueId == widget.leagueId).toList();

    final teams = await _repo.getTeams(widget.leagueId);

    // Resolve profiles silently (no UI prompts).
    final uniqueUserIds = leagueMembers.map((m) => m.userId).where((id) => id.trim().isNotEmpty).toSet().toList();

    final Map<String, String> resolved = {};
    await Future.wait(
      uniqueUserIds.map((uid) async {
        try {
          final p = await _profiles.fetchByUserId(uid);
          if (p != null && p.teamName.trim().isNotEmpty) {
            resolved[uid] = p.teamName.trim();
          }
        } catch (_) {
          // Offline / permission / transient error: ignore and fallback to userId in UI.
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = context.l10n;

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
                const Icon(
                  Icons.people_outline,
                  size: 40,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('league_participants_empty_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.tr('league_participants_empty_subtitle'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final organizers = _memberships.where((m) => m.role == LeagueRole.organizer).toList();
    final members = _memberships.where((m) => m.role == LeagueRole.member).toList();

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
      children: [
        if (organizers.isNotEmpty) ...[
          Text(
            l10n.tr('league_participants_organizers_title'),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...organizers.map(_buildMembershipTile),
          const SizedBox(height: 16),
        ],
        Text(
          l10n.tr('league_participants_participants_title'),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        ...members.map(_buildMembershipTile),
      ],
    );
  }

  Widget _buildMembershipTile(Membership m) {
    final l10n = context.l10n;

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
            backgroundColor: isOrganizer ? Colors.cyanAccent.withOpacity(0.2) : Colors.white.withOpacity(0.08),
            child: Icon(
              isOrganizer ? Icons.verified_user : Icons.person,
              color: isOrganizer ? Colors.cyanAccent : Colors.white70,
              size: 18,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
