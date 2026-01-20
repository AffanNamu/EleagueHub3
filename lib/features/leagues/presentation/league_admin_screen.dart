import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/services/notification_service.dart';
import '../data/leagues_repository_local.dart';
import '../data/league_announcements_local.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../models/league_announcement.dart';
import 'league_participants_screen.dart';
import 'add_teams_screen.dart';

class LeagueAdminScreen extends ConsumerStatefulWidget {
  final bool hasPendingChanges;
  final String leagueId;

  const LeagueAdminScreen({
    super.key,
    this.hasPendingChanges = true,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueAdminScreen> createState() =>
      _LeagueAdminScreenState();
}

class _LeagueAdminScreenState
    extends ConsumerState<LeagueAdminScreen> {
  late LocalLeaguesRepository _localRepo;
  late LeagueAnnouncementsLocal _annRepo;
  League? _league;
  bool _isLeagueLoading = true;
  bool _isSyncing = false;

  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsServiceProvider);
    _localRepo = LocalLeaguesRepository(prefs);
    _annRepo = LeagueAnnouncementsLocal(prefs);
    _loadLeague();
  }

  Future<void> _loadLeague() async {
    final league = await _localRepo.getLeagueById(widget.leagueId);
    if (!mounted) return;
    setState(() {
      _league = league;
      _isLeagueLoading = false;
    });
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
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                            ),
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

  // -------------------
  // Info / status card
  // -------------------
  Widget _buildInfoCard() {
    return Glass(
      borderRadius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              widget.hasPendingChanges
                  ? Icons.cloud_off
                  : Icons.cloud_done,
              color: widget.hasPendingChanges
                  ? Colors.orangeAccent
                  : Colors.greenAccent,
              size: 40,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.hasPendingChanges
                        ? 'Offline Changes'
                        : 'Fully Synced',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.hasPendingChanges
                        ? 'Local edits will sync when you add a backend.'
                        : 'No pending local changes.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
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

  /// Stubbed sync: no backend yet
  Future<void> _syncParticipants() async {
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Offline mode: remote sync is not configured yet.',
        ),
      ),
    );
  }

  // -------------------
  // Settings list
  // -------------------
  Widget _buildSettingsList(BuildContext context) {
    return ListView(
      children: [
        _buildSettingsTile(
          context,
          Icons.group_add,
          'Manage Teams & Participants',
          'Add teams manually or view joined participants',
          onTap: _showParticipantsOptionsSheet,
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
                builder: (_) =>
                    LeagueParticipantsScreen(leagueId: widget.leagueId),
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
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              icon,
              color: isDestructive
                  ? Colors.redAccent
                  : Colors.white,
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.white30,
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  // -------------------
  // Live & Voice Settings (viewer controls)
  // -------------------
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Live & Voice Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white10),
                            SwitchListTile.adaptive(
                              value: chatEnabled,
                              onChanged: (v) =>
                                  setModalState(() => chatEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text(
                                'Viewer text chat',
                                style:
                                    TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                'Allow viewers to type messages',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: voiceEnabled,
                              onChanged: (v) =>
                                  setModalState(() => voiceEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text(
                                'Viewer audio',
                                style:
                                    TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                'Allow viewers to hear the stream',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SwitchListTile.adaptive(
                              value: reactionsEnabled,
                              onChanged: (v) =>
                                  setModalState(() => reactionsEnabled = v),
                              activeColor: Colors.cyanAccent,
                              title: const Text(
                                'Viewer reactions',
                                style:
                                    TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                'Allow quick reactions (GG, Wow, Clutch)',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  right: 4,
                                  bottom: 8,
                                ),
                                child: FilledButton(
                                  onPressed: () async {
                                    await prefs
                                        .setLiveViewerChatEnabled(
                                            chatEnabled);
                                    await prefs
                                        .setLiveViewerVoiceEnabled(
                                            voiceEnabled);
                                    await prefs
                                        .setLiveViewerReactionsEnabled(
                                            reactionsEnabled);

                                    if (!mounted) return;
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Live viewer settings updated.',
                                        ),
                                      ),
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

  // -------------------
  // Send announcement
  // -------------------
  void _showSendAnnouncementSheet() {
    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('League info not loaded yet.'),
        ),
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
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom)
                    .add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Send announcement',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'This message will appear in the league details screen for all participants on this device.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          style: const TextStyle(
                              color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Title (optional)',
                            labelStyle: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: messageController,
                          style: const TextStyle(
                              color: Colors.white),
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Message',
                            labelStyle: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final rawTitle =
                                      titleController.text.trim();
                                  final msg =
                                      messageController.text.trim();
                                  if (msg.isEmpty) return;

                                  final title = rawTitle.isEmpty
                                      ? 'Announcement'
                                      : rawTitle;

                                  final now = DateTime.now()
                                      .millisecondsSinceEpoch;

                                  final ann = LeagueAnnouncement(
                                    id: _uuid.v4(),
                                    leagueId: widget.leagueId,
                                    title: title,
                                    message: msg,
                                    createdAtMs: now,
                                  );

                                  await _annRepo
                                      .addAnnouncement(ann);

                                  await NotificationService()
                                      .showLeagueAnnouncementNotification(
                                    leagueName: _league?.name ??
                                        'League',
                                    title: title,
                                    message: msg,
                                  );

                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Announcement sent (local only).',
                                      ),
                                    ),
                                  );
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

  // -------------------
  // Manage participants / teams
  // -------------------
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
                constraints:
                    const BoxConstraints(maxWidth: 500),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Manage Teams & Participants',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Divider(color: Colors.white10),
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor:
                                Colors.cyanAccent,
                            child: Icon(Icons.group,
                                color: Colors.black),
                          ),
                          title: const Text(
                            'Teams (Add / Edit)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Manually add or review teams',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openAddTeams();
                          },
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white
                                .withOpacity(0.1),
                            child: const Icon(
                              Icons.people,
                              color: Colors.white,
                            ),
                          ),
                          title: const Text(
                            'Joined Participants',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'View users who joined via code / QR',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LeagueParticipantsScreen(
                                  leagueId:
                                      widget.leagueId,
                                ),
                              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'League info not loaded yet. Please try again.',
          ),
        ),
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

  // -------------------
  // League rules editor
  // -------------------
  void _showRulesSheet() {
    if (_league == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('League info not loaded yet.'),
        ),
      );
      return;
    }

    final league = _league!;
    final format = league.format;
    bool doubleRR = league.settings.doubleRoundRobin;
    int groupSize = league.settings.groupSize;
    int swissRounds = league.settings.swissRounds;

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
                    constraints:
                        const BoxConstraints(maxWidth: 520),
                    child: Glass(
                      borderRadius: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'League Rules',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    format.displayName,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Colors.white10),
                            SwitchListTile.adaptive(
                              value: doubleRR,
                              onChanged: (v) => setModalState(
                                () => doubleRR = v,
                              ),
                              activeColor: Colors.cyanAccent,
                              title: const Text(
                                'Double Round-Robin',
                                style: TextStyle(
                                    color: Colors.white),
                              ),
                              subtitle: const Text(
                                'Each pairing plays home & away',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (format ==
                                LeagueFormat.uclGroup)
                              ListTile(
                                contentPadding:
                                    EdgeInsets.zero,
                                title: const Text(
                                  'Teams per Group',
                                  style: TextStyle(
                                      color:
                                          Colors.white),
                                ),
                                subtitle: const Text(
                                  'Recommended: 4 teams per group',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove,
                                        color: Colors
                                            .white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          groupSize =
                                              (groupSize -
                                                      1)
                                                  .clamp(
                                                      2, 8);
                                        });
                                      },
                                    ),
                                    Text(
                                      '$groupSize',
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add,
                                        color: Colors
                                            .white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          groupSize =
                                              (groupSize +
                                                      1)
                                                  .clamp(
                                                      2, 8);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            if (format ==
                                LeagueFormat.uclSwiss)
                              ListTile(
                                contentPadding:
                                    EdgeInsets.zero,
                                title: const Text(
                                  'Swiss Rounds',
                                  style: TextStyle(
                                      color:
                                          Colors.white),
                                ),
                                subtitle: const Text(
                                  'Number of Swiss rounds before knockouts',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove,
                                        color: Colors
                                            .white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          swissRounds =
                                              (swissRounds -
                                                      1)
                                                  .clamp(
                                                      1, 20);
                                        });
                                      },
                                    ),
                                    Text(
                                      '$swissRounds',
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add,
                                        color: Colors
                                            .white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          swissRounds =
                                              (swissRounds +
                                                      1)
                                                  .clamp(
                                                      1, 20);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            Align(
                              alignment:
                                  Alignment.centerRight,
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(
                                  top: 8,
                                  right: 4,
                                  bottom: 8,
                                ),
                                child: FilledButton(
                                  onPressed: () async {
                                    final updatedSettings =
                                        league
                                            .settings
                                            .copyWith(
                                      doubleRoundRobin:
                                          doubleRR,
                                      groupSize:
                                          groupSize,
                                      swissRounds:
                                          swissRounds,
                                      lastPulledAtMs: league
                                          .settings
                                          .lastPulledAtMs,
                                    );

                                    final updatedLeague =
                                        league.copyWith(
                                      settings:
                                          updatedSettings,
                                      updatedAtMs: DateTime
                                              .now()
                                          .millisecondsSinceEpoch,
                                    );

                                    await _localRepo
                                        .saveLeague(
                                            updatedLeague);

                                    if (!mounted) return;
                                    setState(() {
                                      _league =
                                          updatedLeague;
                                    });

                                    Navigator.of(ctx)
                                        .pop();
                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'League rules updated.',
                                        ),
                                      ),
                                    );
                                  },
                                  child:
                                      const Text('Save'),
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

  // -------------------
  // Delete league
  // -------------------
  void _confirmDeleteLeague() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1D37),
          title: const Text(
            'Delete League?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'This will permanently remove this league and all of its local data. '
            'This action cannot be undone.',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                    color: Colors.white70),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    Colors.redAccent,
              ),
              onPressed: () async {
                await _localRepo
                    .deleteLeagueCompletely(
                        widget.leagueId);

                if (!mounted) return;
                Navigator.of(ctx).pop(); // close dialog

                GoRouter.of(context)
                    .go('/leagues');

                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  const SnackBar(
                    content: Text('League deleted.'),
                  ),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
