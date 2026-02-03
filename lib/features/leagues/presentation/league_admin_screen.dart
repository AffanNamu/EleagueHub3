import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../data/league_announcements_local.dart';
import '../data/league_spaces_local.dart';
import '../data/leagues_repository_local.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_space.dart';
import '../models/team.dart';
import '../utils/current_user.dart';
import 'add_teams_screen.dart';
import 'league_participants_screen.dart';
import 'utils/roster_csv_exporter.dart';

class LeagueAdminScreen extends ConsumerStatefulWidget {
  final bool hasPendingChanges;
  final String leagueId;

  const LeagueAdminScreen({
    super.key,
    this.hasPendingChanges = true,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueAdminScreen> createState() => _LeagueAdminScreenState();
}

class _LeagueAdminScreenState extends ConsumerState<LeagueAdminScreen> {
  late LocalLeaguesRepository _localRepo;
  late LeagueAnnouncementsFirebase _annRepo;
  late LeagueSpacesFirebase _spaceRepo;

  League? _league;
  LeagueSpace? _space;

  bool _isLeagueLoading = true;
  bool _isSyncing = false;
  bool _exportingRoster = false;

  bool _showAddMeAsParticipant = false;
  bool _addingMeAsParticipant = false;

  final Uuid _uuid = const Uuid();

  static const List<String> _groupNames = <String>[
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
  ];

  String _groupDisplayName(AppLocalizations l10n, String groupId) {
    final g = groupId.trim();
    if (g == 'Group A') return l10n.tr('add_teams_group_a');
    if (g == 'Group B') return l10n.tr('add_teams_group_b');
    if (g == 'Group C') return l10n.tr('add_teams_group_c');
    if (g == 'Group D') return l10n.tr('add_teams_group_d');
    if (g == 'Group E') return l10n.tr('add_teams_group_e');
    if (g == 'Group F') return l10n.tr('add_teams_group_f');
    if (g == 'Group G') return l10n.tr('add_teams_group_g');
    if (g == 'Group H') return l10n.tr('add_teams_group_h');
    return g;
  }

  List<String> _allowedGroupsForUclGroup(League league) {
    // Enforce your supported sizes:
    // - 16 teams => 4 groups (A–D)
    // - 32 teams => 8 groups (A–H)
    final max = league.maxTeams;
    if (max == 16) return _groupNames.take(4).toList();
    return _groupNames.take(8).toList();
  }

  String? _pickGroupWithSpace({
    required List<Team> teams,
    required List<String> allowedGroups,
  }) {
    final counts = <String, int>{for (final g in allowedGroups) g: 0};
    for (final t in teams) {
      final g = (t.groupId ?? '').trim();
      if (counts.containsKey(g)) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }

    // Choose a group with <4 teams (to preserve group size 4).
    final available = counts.entries.where((e) => e.value < 4).toList();
    if (available.isEmpty) return null;

    // Pick the smallest count; random tie-break.
    available.sort((a, b) => a.value.compareTo(b.value));
    final min = available.first.value;
    final minGroups = available.where((e) => e.value == min).map((e) => e.key).toList();

    final rnd = Random.secure();
    return minGroups[rnd.nextInt(minGroups.length)];
  }

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsFirebase(prefs);
    _spaceRepo = LeagueSpacesFirebase(prefs);
    _loadLeague();

    // Pull latest from cloud for space/announcements status
    // ignore: discarded_futures
    SyncTrigger.trySync().then((_) => _loadLeague());
  }

  Future<void> _loadLeague() async {
    final league = await _localRepo.getLeagueById(widget.leagueId);
    final space = await _spaceRepo.getSpace(widget.leagueId);

    bool showAddMe = false;

    try {
      final currentUserId = await CurrentUser.getUserId();
      final isOrganizer = league != null && league.organizerUserId == currentUserId;

      if (isOrganizer) {
        final teams = await _localRepo.getTeams(widget.leagueId);
        final alreadyParticipant = teams.any((t) => t.id == currentUserId);
        showAddMe = !alreadyParticipant;
      }
    } catch (_) {
      showAddMe = false;
    }

    if (!mounted) return;
    setState(() {
      _league = league;
      _space = space;
      _showAddMeAsParticipant = showAddMe;
      _isLeagueLoading = false;
    });
  }

  Future<void> _addMeAsParticipant() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_admin_league_info_not_loaded_yet'))),
      );
      return;
    }

    if (_addingMeAsParticipant) return;

    setState(() => _addingMeAsParticipant = true);

    try {
      final userId = await CurrentUser.getUserId();

      // Enforce organiser-only
      if (league.organizerUserId != userId) {
        throw StateError(l10n.tr('league_admin_only_organizer_action'));
      }

      // Enforce supported team counts via maxTeams for fixed-size formats
      if (league.format == LeagueFormat.uclGroup && !(league.maxTeams == 16 || league.maxTeams == 32)) {
        throw StateError(l10n.tr('league_admin_ucl_group_maxteams_error'));
      }
      if (league.format == LeagueFormat.uclSwiss && !(league.maxTeams == 18 || league.maxTeams == 36)) {
        throw StateError(l10n.tr('league_admin_swiss_maxteams_error'));
      }

      final existingTeams = await _localRepo.getTeams(league.id);
      final alreadyHasTeam = existingTeams.any((t) => t.id == userId);
      if (alreadyHasTeam) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr('league_admin_already_added_participant_team_exists')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Prevent exceeding maxTeams (roster capacity)
      if (existingTeams.length >= league.maxTeams) {
        throw StateError(
          '${l10n.tr('league_admin_league_full_prefix')}${league.maxTeams}${l10n.tr('league_admin_league_full_suffix')}',
        );
      }

      final profile = await UserProfileRepository().fetchByUserId(userId);
      final teamName = profile?.teamName.trim() ?? '';
      if (teamName.isEmpty) {
        throw StateError(l10n.tr('league_admin_profile_team_name_missing'));
      }

      // Assign group if needed, ensuring group sizes remain 4.
      String? groupId;
      if (league.format == LeagueFormat.uclGroup) {
        final allowedGroups = _allowedGroupsForUclGroup(league);
        final picked = _pickGroupWithSpace(teams: existingTeams, allowedGroups: allowedGroups);
        if (picked == null) {
          throw StateError(l10n.tr('league_admin_all_groups_full'));
        }
        groupId = picked;
      } else {
        groupId = null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      final team = Team(
        id: userId,
        leagueId: league.id,
        name: teamName,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );

      await _localRepo.saveTeams(league.id, <Team>[...existingTeams, team]);

      await _localRepo.assignTeamToUserInLeague(
        leagueId: league.id,
        userId: userId,
        teamId: userId,
      );

      if (!mounted) return;

      await _loadLeague();

      final msg = groupId == null
          ? l10n.tr('league_admin_added_participant')
          : '${l10n.tr('league_admin_added_participant_in_group_prefix')} ${_groupDisplayName(l10n, groupId)}.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_admin_failed_add_participant_prefix')} $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _addingMeAsParticipant = false);
    }
  }

  Future<void> _exportRosterCsv() async {
    final l10n = context.l10n;
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_admin_league_info_not_loaded_yet'))),
      );
      return;
    }

    if (_exportingRoster) return;

    setState(() => _exportingRoster = true);
    try {
      await RosterCsvExporter.shareRosterCsv(
        repo: _localRepo,
        league: league,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.tr('league_admin_export_failed_prefix')} $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingRoster = false);
    }
  }

  Future<void> _startSpace() async {
    final l10n = context.l10n;

    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_admin_league_info_not_loaded_yet'))),
      );
      return;
    }

    try {
      final prefs = ref.read(prefsServiceProvider);
      final currentUserId = prefs.getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError(l10n.tr('league_admin_no_signed_in_user_error'));
      }

      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        throw StateError(l10n.tr('league_admin_only_organizer_start_space'));
      }

      final space = await _spaceRepo.startSpace(
        leagueId: _league!.id,
        hostUserId: currentUserId,
        title: '${_league!.name} ${l10n.tr('league_details_space_title_suffix')}',
      );

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() => _space = space);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_details_space_started')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_details_failed_to_start_space')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endSpace() async {
    final l10n = context.l10n;

    if (_league == null) return;

    try {
      final prefs = ref.read(prefsServiceProvider);
      final currentUserId = prefs.getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError(l10n.tr('league_admin_no_signed_in_user_error'));
      }

      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        throw StateError(l10n.tr('league_admin_only_organizer_end_space'));
      }

      final updated = await _spaceRepo.endSpace(_league!.id);

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() => _space = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_details_space_ended')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_details_failed_to_end_space')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onOpenSpace() {
    final l10n = context.l10n;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.tr('league_admin_opening_space_not_implemented')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_admin_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _isLeagueLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.cyanAccent),
                          )
                        : _buildSettingsList(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final l10n = context.l10n;

    return Glass(
      borderRadius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              widget.hasPendingChanges ? Icons.cloud_off : Icons.cloud_done,
              color: widget.hasPendingChanges ? Colors.orangeAccent : Colors.greenAccent,
              size: 40,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.hasPendingChanges
                        ? l10n.tr('league_admin_offline_changes_title')
                        : l10n.tr('league_admin_fully_synced_title'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    widget.hasPendingChanges
                        ? l10n.tr('league_admin_offline_changes_subtitle')
                        : l10n.tr('league_admin_fully_synced_subtitle'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.tr('league_admin_sync_now_tooltip'),
              onPressed: () async {
                await SyncTrigger.trySync();
                await _loadLeague();
              },
              icon: const Icon(Icons.sync, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncParticipants() async {
    final l10n = context.l10n;

    setState(() => _isSyncing = true);
    await SyncTrigger.trySync();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('league_admin_sync_complete'))),
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    final l10n = context.l10n;
    final spaceLive = _space?.isLive == true;

    return ListView(
      children: [
        _buildSettingsTile(
          context,
          Icons.group_add,
          l10n.tr('league_admin_manage_teams_title'),
          l10n.tr('league_admin_manage_teams_subtitle'),
          onTap: _showParticipantsOptionsSheet,
        ),
        if (_showAddMeAsParticipant)
          _buildSettingsTile(
            context,
            Icons.person_add_alt_1,
            _addingMeAsParticipant ? l10n.tr('league_admin_adding_you') : l10n.tr('league_admin_add_me_participant'),
            l10n.tr('league_admin_add_me_participant_subtitle'),
            onTap: _addingMeAsParticipant ? null : _addMeAsParticipant,
          ),
        _buildSettingsTile(
          context,
          Icons.file_download_outlined,
          _exportingRoster ? l10n.tr('league_admin_exporting_roster') : l10n.tr('league_admin_export_roster'),
          l10n.tr('league_admin_export_roster_subtitle'),
          onTap: _exportingRoster ? null : _exportRosterCsv,
        ),
        _buildSettingsTile(
          context,
          Icons.people_outline,
          l10n.tr('league_admin_view_participants'),
          l10n.tr('league_admin_view_participants_subtitle'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LeagueParticipantsScreen(leagueId: widget.leagueId),
              ),
            );
          },
        ),
        _buildSettingsTile(
          context,
          Icons.mic,
          l10n.tr('league_admin_live_voice_settings'),
          l10n.tr('league_admin_live_voice_settings_subtitle'),
          onTap: _showLiveSettingsSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.spatial_audio_off,
          spaceLive ? l10n.tr('league_admin_league_space_live') : l10n.tr('league_admin_league_space_voice_room'),
          spaceLive
              ? l10n.tr('league_admin_league_space_live_subtitle')
              : l10n.tr('league_admin_league_space_voice_room_subtitle'),
          onTap: _showLeagueSpaceAdminSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.notifications_active,
          l10n.tr('league_admin_send_announcement'),
          l10n.tr('league_admin_send_announcement_subtitle'),
          onTap: _showSendAnnouncementSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.rule,
          l10n.tr('league_admin_league_rules'),
          l10n.tr('league_admin_league_rules_subtitle'),
          onTap: _showRulesSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.sync,
          l10n.tr('league_admin_sync_now'),
          _isSyncing ? l10n.tr('league_admin_syncing') : l10n.tr('league_admin_sync_now_subtitle'),
          onTap: _isSyncing ? null : _syncParticipants,
        ),
        _buildSettingsTile(
          context,
          Icons.delete_forever,
          l10n.tr('league_admin_delete_league'),
          l10n.tr('league_admin_delete_league_subtitle'),
          isDestructive: true,
          onTap: _confirmDeleteLeague,
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final chevronIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white),
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: Icon(chevronIcon, color: Colors.white30),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  void _showLiveSettingsSheet() {
    final l10n = context.l10n;
    final prefs = ref.read(prefsServiceProvider);

    bool chatEnabled = prefs.liveViewerChatEnabled();
    bool voiceEnabled = prefs.liveViewerVoiceEnabled();
    bool reactionsEnabled = prefs.liveViewerReactionsEnabled();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Glass(
                      borderRadius: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                l10n.tr('league_admin_live_voice_settings'),
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Divider(color: Colors.white10),
                            SwitchListTile.adaptive(
                              value: chatEnabled,
                              onChanged: (v) => setModalState(() => chatEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: Text(l10n.tr('league_admin_viewer_text_chat'), style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_text_chat_subtitle'),
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: voiceEnabled,
                              onChanged: (v) => setModalState(() => voiceEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: Text(l10n.tr('league_admin_viewer_audio'), style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_audio_subtitle'),
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: reactionsEnabled,
                              onChanged: (v) => setModalState(() => reactionsEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: Text(l10n.tr('league_admin_viewer_reactions'), style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                l10n.tr('league_admin_viewer_reactions_subtitle'),
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8, right: 4, bottom: 8),
                                child: FilledButton(
                                  onPressed: () async {
                                    await prefs.setLiveViewerChatEnabled(chatEnabled);
                                    await prefs.setLiveViewerVoiceEnabled(voiceEnabled);
                                    await prefs.setLiveViewerReactionsEnabled(reactionsEnabled);

                                    if (!mounted) return;
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l10n.tr('league_admin_live_viewer_settings_updated'))),
                                    );
                                  },
                                  child: Text(l10n.tr('common_save')),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLeagueSpaceAdminSheet() {
    final l10n = context.l10n;
    final leagueName = _league?.name ?? l10n.tr('common_league_placeholder');
    final spaceLive = _space?.isLive == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr('league_admin_league_space_sheet_title'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          spaceLive
                              ? '${l10n.tr('league_admin_league_space_running_prefix')} $leagueName.'
                              : '${l10n.tr('league_admin_league_space_start_description_prefix')} $leagueName${l10n.tr('league_admin_league_space_start_description_suffix')}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (!spaceLive) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(l10n.tr('profile_close_tooltip'),
                                      style: const TextStyle(color: Colors.white70)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _startSpace();
                                  },
                                  icon: const Icon(Icons.mic),
                                  label: Text(l10n.tr('league_admin_start_space')),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _onOpenSpace();
                                  },
                                  icon: const Icon(Icons.headset),
                                  label: Text(l10n.tr('league_admin_open_space')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _endSpace();
                                  },
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: Text(l10n.tr('league_admin_end_space')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSendAnnouncementSheet() {
    final l10n = context.l10n;

    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_admin_league_info_not_loaded_yet'))),
      );
      return;
    }

    final titleController = TextEditingController();
    final messageController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr('league_admin_send_announcement_sheet_title'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tr('league_admin_send_announcement_sheet_subtitle'),
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: l10n.tr('league_admin_announcement_title_optional'),
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: messageController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l10n.tr('league_admin_announcement_message_label'),
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(l10n.tr('common_cancel'), style: const TextStyle(color: Colors.white70)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final rawTitle = titleController.text.trim();
                                  final msg = messageController.text.trim();
                                  if (msg.isEmpty) return;

                                  final title =
                                      rawTitle.isEmpty ? l10n.tr('league_admin_announcement_default_title') : rawTitle;
                                  final now = DateTime.now().millisecondsSinceEpoch;

                                  final ann = LeagueAnnouncement(
                                    id: _uuid.v4(),
                                    leagueId: widget.leagueId,
                                    title: title,
                                    message: msg,
                                    createdAtMs: now,
                                  );

                                  await _annRepo.addAnnouncement(ann);

                                  await NotificationService().showLeagueAnnouncementNotification(
                                    leagueName: _league?.name ?? l10n.tr('common_league_placeholder'),
                                    title: title,
                                    message: msg,
                                  );

                                  await SyncTrigger.trySync();

                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.tr('league_admin_announcement_sent'))),
                                  );
                                },
                                child: Text(l10n.tr('league_admin_send')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showParticipantsOptionsSheet() {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            l10n.tr('league_admin_manage_teams_title'),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(color: Colors.white10),
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.cyanAccent,
                            child: Icon(Icons.group, color: Colors.black),
                          ),
                          title: Text(
                            l10n.tr('league_admin_teams_add_edit_title'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            l10n.tr('league_admin_teams_add_edit_subtitle'),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openAddTeams();
                          },
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.1),
                            child: const Icon(Icons.people, color: Colors.white),
                          ),
                          title: Text(
                            l10n.tr('league_admin_joined_participants_title'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            l10n.tr('league_admin_joined_participants_subtitle'),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => LeagueParticipantsScreen(leagueId: widget.leagueId)),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openAddTeams() {
    final l10n = context.l10n;

    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_admin_league_info_not_loaded_yet_try_again'))),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTeamsScreen(
          leagueId: widget.leagueId,
          format: _league!.format,
        ),
      ),
    );
  }

  void _showRulesSheet() {
    final l10n = context.l10n;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('league_admin_rules_editor_unchanged'))),
    );
  }

  void _confirmDeleteLeague() {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1D37),
          title: Text(
            l10n.tr('league_admin_delete_league_confirm_title'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            l10n.tr('league_admin_delete_league_confirm_message'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.tr('common_cancel'), style: const TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                await _localRepo.deleteLeagueCompletely(widget.leagueId);

                if (!mounted) return;
                Navigator.of(ctx).pop();

                GoRouter.of(context).go('/leagues');

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.tr('league_admin_league_deleted'))),
                );
              },
              child: Text(l10n.tr('league_admin_delete')),
            ),
          ],
        );
      },
    );
  }
}
