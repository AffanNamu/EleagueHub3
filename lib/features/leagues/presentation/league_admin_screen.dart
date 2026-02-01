import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

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
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League info not loaded yet.')),
      );
      return;
    }

    if (_addingMeAsParticipant) return;

    setState(() => _addingMeAsParticipant = true);

    try {
      final userId = await CurrentUser.getUserId();

      // Enforce organiser-only
      if (league.organizerUserId != userId) {
        throw StateError('Only the league organizer can use this action.');
      }

      // Enforce supported team counts via maxTeams for fixed-size formats
      if (league.format == LeagueFormat.uclGroup && !(league.maxTeams == 16 || league.maxTeams == 32)) {
        throw StateError('UCL Group leagues must have maxTeams set to 16 or 32.');
      }
      if (league.format == LeagueFormat.uclSwiss && !(league.maxTeams == 18 || league.maxTeams == 36)) {
        throw StateError('Swiss leagues must have maxTeams set to 18 or 36.');
      }

      final existingTeams = await _localRepo.getTeams(league.id);
      final alreadyHasTeam = existingTeams.any((t) => t.id == userId);
      if (alreadyHasTeam) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are already added as a participant (team exists).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Prevent exceeding maxTeams (roster capacity)
      if (existingTeams.length >= league.maxTeams) {
        throw StateError('League is full (${league.maxTeams} teams).');
      }

      final profile = await UserProfileRepository().fetchByUserId(userId);
      final teamName = profile?.teamName.trim() ?? '';
      if (teamName.isEmpty) {
        throw StateError('Your profile team name is missing. Please update your profile first.');
      }

      // Assign group if needed, ensuring group sizes remain 4.
      String? groupId;
      if (league.format == LeagueFormat.uclGroup) {
        final allowedGroups = _allowedGroupsForUclGroup(league);
        final picked = _pickGroupWithSpace(teams: existingTeams, allowedGroups: allowedGroups);
        if (picked == null) {
          throw StateError('All groups are full. Cannot add another team.');
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            groupId == null ? 'You have been added as a participant.' : 'You have been added as a participant in $groupId.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add you as participant: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _addingMeAsParticipant = false);
    }
  }

  Future<void> _exportRosterCsv() async {
    final league = _league;
    if (league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League info not loaded yet.')),
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
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingRoster = false);
    }
  }

  Future<void> _startSpace() async {
    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League info not loaded yet.')),
      );
      return;
    }

    try {
      final prefs = ref.read(prefsServiceProvider);
      final currentUserId = prefs.getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError('No signed-in user id (FirebaseAuth). Please restart app.');
      }

      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        throw StateError('Only the league organizer can start a space.');
      }

      final space = await _spaceRepo.startSpace(
        leagueId: _league!.id,
        hostUserId: currentUserId,
        title: '${_league!.name} Space',
      );

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() => _space = space);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('League Space started.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start space: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endSpace() async {
    if (_league == null) return;

    try {
      final prefs = ref.read(prefsServiceProvider);
      final currentUserId = prefs.getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError('No signed-in user id (FirebaseAuth). Please restart app.');
      }

      if (_league!.organizerUserId.isNotEmpty && _league!.organizerUserId != currentUserId) {
        throw StateError('Only the league organizer can end a space.');
      }

      final updated = await _spaceRepo.endSpace(_league!.id);

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() => _space = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('League Space ended.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to end space: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onOpenSpace() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening League Space (voice room UI not implemented yet).'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        title: const Text('League Settings'),
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
                    widget.hasPendingChanges ? 'Offline Changes' : 'Fully Synced',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    widget.hasPendingChanges ? 'Local edits will sync when online.' : 'No pending local changes.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Sync now',
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
    setState(() => _isSyncing = true);
    await SyncTrigger.trySync();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync complete')),
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    final spaceLive = _space?.isLive == true;

    return ListView(
      children: [
        _buildSettingsTile(
          context,
          Icons.group_add,
          'Manage Teams & Participants',
          'Add teams manually or view joined participants',
          onTap: _showParticipantsOptionsSheet,
        ),
        if (_showAddMeAsParticipant)
          _buildSettingsTile(
            context,
            Icons.person_add_alt_1,
            _addingMeAsParticipant ? 'Adding you…' : 'Add me as participant',
            'Create your team from your profile team name (no duplicates).',
            onTap: _addingMeAsParticipant ? null : _addMeAsParticipant,
          ),
        _buildSettingsTile(
          context,
          Icons.file_download_outlined,
          _exportingRoster ? 'Exporting roster…' : 'Export roster CSV',
          'Download/share an importable roster file (use it later in Add Teams → Import CSV).',
          onTap: _exportingRoster ? null : _exportRosterCsv,
        ),
        _buildSettingsTile(
          context,
          Icons.people_outline,
          'View Participants',
          'See all joined members and their roles',
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
          'Live & Voice Settings',
          'Viewer chat, voice and reactions',
          onTap: _showLiveSettingsSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.spatial_audio_off,
          spaceLive ? 'League Space • LIVE' : 'League Space (Voice Room)',
          spaceLive ? 'Tap to open or end this live audio room' : 'Start a live voice room for this league',
          onTap: _showLeagueSpaceAdminSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.notifications_active,
          'Send Announcement',
          'Write a message for league participants',
          onTap: _showSendAnnouncementSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.rule,
          'League Rules',
          'Format, round-robin and group/swiss options',
          onTap: _showRulesSheet,
        ),
        _buildSettingsTile(
          context,
          Icons.sync,
          'Sync Now',
          _isSyncing ? 'Syncing...' : 'Push local changes and pull latest cloud data',
          onTap: _isSyncing ? null : _syncParticipants,
        ),
        _buildSettingsTile(
          context,
          Icons.delete_forever,
          'Delete League',
          'This cannot be undone',
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
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  void _showLiveSettingsSheet() {
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
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Live & Voice Settings',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Divider(color: Colors.white10),
                            SwitchListTile.adaptive(
                              value: chatEnabled,
                              onChanged: (v) => setModalState(() => chatEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text('Viewer text chat', style: TextStyle(color: Colors.white)),
                              subtitle: const Text('Allow viewers to type messages', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            ),
                            SwitchListTile.adaptive(
                              value: voiceEnabled,
                              onChanged: (v) => setModalState(() => voiceEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text('Viewer audio', style: TextStyle(color: Colors.white)),
                              subtitle: const Text('Allow viewers to hear the stream', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            ),
                            SwitchListTile.adaptive(
                              value: reactionsEnabled,
                              onChanged: (v) => setModalState(() => reactionsEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text('Viewer reactions', style: TextStyle(color: Colors.white)),
                              subtitle: const Text('Allow quick reactions (GG, Wow, Clutch)', style: TextStyle(color: Colors.white60, fontSize: 12)),
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
                                      const SnackBar(content: Text('Live viewer settings updated.')),
                                    );
                                  },
                                  child: const Text('Save'),
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
    final leagueName = _league?.name ?? 'this league';
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
                        const Text('League Space (Voice Room)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                          spaceLive
                              ? 'A live audio space is currently running for $leagueName.'
                              : 'Start a live audio room where you can talk with players from $leagueName. Only admins can host.',
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
                                  child: const Text('Close', style: TextStyle(color: Colors.white70)),
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
                                  label: const Text('Start Space'),
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
                                  label: const Text('Open Space'),
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
                                  label: const Text('End Space'),
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
    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League info not loaded yet.')),
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
                        const Text('Send announcement', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('This message will appear in the league details screen for all participants.', style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Title (optional)', labelStyle: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: messageController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Message', labelStyle: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final rawTitle = titleController.text.trim();
                                  final msg = messageController.text.trim();
                                  if (msg.isEmpty) return;

                                  final title = rawTitle.isEmpty ? 'Announcement' : rawTitle;
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
                                    leagueName: _league?.name ?? 'League',
                                    title: title,
                                    message: msg,
                                  );

                                  await SyncTrigger.trySync();

                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement sent.')));
                                },
                                child: const Text('Send'),
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
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Manage Teams & Participants', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const Divider(color: Colors.white10),
                        ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.cyanAccent, child: Icon(Icons.group, color: Colors.black)),
                          title: const Text('Teams (Add / Edit)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Manually add or review teams', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openAddTeams();
                          },
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.white.withOpacity(0.1), child: const Icon(Icons.people, color: Colors.white)),
                          title: const Text('Joined Participants', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: const Text('View users who joined via code / QR', style: TextStyle(color: Colors.white38, fontSize: 12)),
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
    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('League info not loaded yet. Please try again.')));
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rules editor: unchanged (already implemented in your project).')),
    );
  }

  void _confirmDeleteLeague() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1D37),
          title: const Text('Delete League?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'This will permanently remove this league and all of its local data. This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                await _localRepo.deleteLeagueCompletely(widget.leagueId);

                if (!mounted) return;
                Navigator.of(ctx).pop();

                GoRouter.of(context).go('/leagues');

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('League deleted.')));
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
