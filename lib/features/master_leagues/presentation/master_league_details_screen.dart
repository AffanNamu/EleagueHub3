import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../widgets/league_flip_card.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/data/league_announcements_firebase.dart';
import '../../leagues/data/leagues_repository_local.dart';
import '../../leagues/models/enums.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_announcement.dart';
import '../../leagues/models/league_format.dart';
import '../../leagues/models/membership.dart';
import '../../leagues/presentation/widgets/join_league_mode_sheet.dart';
import '../domain/competition_template.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';
import 'organizer_profile_screen.dart';

class MasterLeagueDetailsScreen extends ConsumerStatefulWidget {
  const MasterLeagueDetailsScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  ConsumerState<MasterLeagueDetailsScreen> createState() =>
      _MasterLeagueDetailsScreenState();
}

class _MasterLeagueDetailsScreenState
    extends ConsumerState<MasterLeagueDetailsScreen> {
  bool _busy = false;
  bool _followBusy = false;
  String? _joiningLeagueId;

  final LeagueAnnouncementsFirebase _announcements =
      LeagueAnnouncementsFirebase();

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool _isOwner(MasterLeague? ml) {
    if (ml == null) return false;
    return ml.ownerId.trim() == _currentUid && _currentUid.isNotEmpty;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<String> _ownerDisplayName(String ownerId) async {
    try {
      final profile = await UserProfileRepository().fetchByUserId(ownerId.trim());
      if (profile != null && profile.displayName.trim().isNotEmpty) {
        return profile.displayName.trim();
      }
    } catch (_) {}
    final shortId = UserProfile.deriveShareIdFromUid(ownerId.trim());
    if (shortId.isNotEmpty) return shortId;
    return 'Organizer';
  }

  Future<void> _toggleFollow(MasterLeague master) async {
    if (_isOwner(master)) return;
    if (_followBusy) return;

    setState(() => _followBusy = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      await repo.toggleFollowWorkspace(master.id);
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Stream<MasterLeague?> _watchMasterLeague(String id) {
    return FirebaseFirestore.instance
        .collection('master_leagues')
        .doc(id.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      if (!snap.exists) return null;
      return MasterLeague.fromMap(
        snap.id,
        (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>(),
      );
    }).handleError((_) => null);
  }

  Stream<List<League>> _watchCompetitions(String masterId) {
    return FirebaseFirestore.instance
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterId.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true
            ? map['id']
            : d.id;
        return League.fromRemoteMap(map);
      }).toList(growable: false);

      final sorted = [...list];
      sorted.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return sorted;
    }).handleError((_) => <League>[]);
  }

  Stream<List<LeagueAnnouncement>> _watchWorkspaceAnnouncements(
      String masterLeagueId) {
    return _announcements.watchMasterLeagueAnnouncements(masterLeagueId);
  }

  Stream<LeagueAnnouncement?> _watchPinnedWorkspaceAnnouncement(
      String masterLeagueId) {
    return _announcements.watchPinnedMasterLeagueAnnouncement(masterLeagueId);
  }

  Future<Membership?> _membershipForLeague(String leagueId) {
    final uid = _currentUid.trim();
    if (uid.isEmpty) return Future<Membership?>.value(null);
    final repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    return repo.getMembership(leagueId: leagueId, userId: uid);
  }

  Future<void> _promptJoinCompetition(League league) async {
    final uid = _currentUid.trim();
    if (uid.isEmpty) {
      _snack('Please sign in and try again.', error: true);
      return;
    }

    if (_joiningLeagueId == league.id) return;

    final repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));

    Membership? existing;
    try {
      existing = await repo.getMembership(leagueId: league.id, userId: uid);
    } catch (_) {}

    if (existing != null) {
      _snack('You already joined this competition.');
      return;
    }

    final selectedMode = await showJoinLeagueModeSheet(
      context,
      league: league,
      title: 'Join Competition',
    );

    if (selectedMode == null) return;

    if (mounted) setState(() => _joiningLeagueId = league.id);

    try {
      await repo.joinLeagueDirect(
        leagueId: league.id,
        mode: selectedMode,
      );

      if (!mounted) return;

      _snack(
        selectedMode == LeagueJoinMode.viewer
            ? 'Competition added to your list as viewer.'
            : 'Successfully joined competition.',
      );
    } catch (e) {
      if (!mounted) return;
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _joiningLeagueId = null);
    }
  }

  Future<void> _showCreateCompetitionSheet(
    BuildContext context,
    MasterLeague? ml,
  ) async {
    if (ml == null || !_isOwner(ml)) {
      _snack(
        'Only the Master League owner can create competitions.',
        error: true,
      );
      return;
    }

    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      await repo.checkLeagueLimitOrThrow(widget.masterLeagueId);
    } catch (e) {
      _snack('$e', error: true);
      return;
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final selected = await showModalBottomSheet<LeagueFormat>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required LeagueFormat format,
          Color? tint,
        }) {
          final c = tint ?? cs.primary;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => Navigator.of(ctx).pop(format),
              borderRadius: BorderRadius.circular(20),
              child: Glass(
                borderRadius: 20,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.withOpacity(0.12),
                        border: Border.all(color: c.withOpacity(0.30)),
                      ),
                      child: Icon(icon, color: c, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurface.withOpacity(0.35),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Glass(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Create Competition',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                option(
                  icon: Icons.emoji_events_outlined,
                  title: 'Classic League',
                  subtitle: 'Round-robin style competition',
                  format: LeagueFormat.classic,
                  tint: cs.primary,
                ),
                option(
                  icon: Icons.grid_view_rounded,
                  title: 'Swiss League',
                  subtitle: 'Swiss/Series format',
                  format: LeagueFormat.uclSwiss,
                  tint: const Color(0xFF8B5CF6),
                ),
                option(
                  icon: Icons.groups_rounded,
                  title: 'UCL Group League',
                  subtitle: 'Group stage competition',
                  format: LeagueFormat.uclGroup,
                  tint: const Color(0xFF22C55E),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    if (!context.mounted) return;

    context.push('/leagues/create', extra: <String, dynamic>{
      'masterLeagueId': widget.masterLeagueId.trim(),
      'initialFormat': selected,
      'type': selected == LeagueFormat.classic
          ? 'classic'
          : (selected == LeagueFormat.uclSwiss ? 'swiss' : 'ucl'),
      if (ml.maxTeamsPerLeague > 0) 'maxTeams': ml.maxTeamsPerLeague,
    });
  }

  Future<void> _showAnnouncementComposer(MasterLeague ml) async {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();

    final shouldPost = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Organizer Announcement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.campaign_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: messageCtrl,
                maxLines: 5,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Post'),
          ),
        ],
      ),
    );

    if (shouldPost != true) {
      titleCtrl.dispose();
      messageCtrl.dispose();
      return;
    }

    final title = titleCtrl.text.trim();
    final message = messageCtrl.text.trim();
    titleCtrl.dispose();
    messageCtrl.dispose();

    if (title.isEmpty || message.isEmpty) {
      _snack('Please enter both title and message.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final ownerProfile = await UserProfileRepository().fetchByUserId(_currentUid);
      final authorName = ownerProfile?.displayName.trim().isNotEmpty == true
          ? ownerProfile!.displayName.trim()
          : 'Organizer';

      await _announcements.addMasterLeagueAnnouncement(
        masterLeagueId: ml.id,
        title: title,
        message: message,
        authorId: _currentUid,
        authorName: authorName,
      );

      _snack('Announcement posted.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pinAnnouncement(LeagueAnnouncement ann) async {
    setState(() => _busy = true);
    try {
      await _announcements.pinMasterLeagueAnnouncement(
        masterLeagueId: ann.masterLeagueId,
        announcementId: ann.id,
        pinnedBy: _currentUid,
      );
      _snack('Announcement pinned.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpinAnnouncement(LeagueAnnouncement ann) async {
    setState(() => _busy = true);
    try {
      await _announcements.unpinMasterLeagueAnnouncement(
        announcementId: ann.id,
      );
      _snack('Announcement unpinned.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteAnnouncement(LeagueAnnouncement ann) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete announcement?',
          style: TextStyle(color: cs.error),
        ),
        content: Text('Delete "${ann.title}" from organizer announcements?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _announcements.deleteAnnouncement(ann.id);
      _snack('Announcement deleted.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRenameDialog(MasterLeague ml) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = TextEditingController(text: ml.name);

    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rename Master League',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                decoration: const InputDecoration(
                  labelText: 'New Name',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                      child: const Text(
                        'Rename',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();

    if (newName == null || newName.isEmpty || newName == ml.name.trim()) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).rename(
            masterLeagueId: widget.masterLeagueId,
            newName: newName,
          );
      _snack('Renamed to "$newName"');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAddStaffDialog({
    required String role,
  }) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = TextEditingController();

    final shortId = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Glass(
          borderRadius: 28,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add ${role == 'admin' ? 'Admin' : 'Moderator'}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the user short id (share id). Example: eS44e35f',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                decoration: InputDecoration(
                  labelText: 'Short ID',
                  prefixIcon: Icon(
                    role == 'admin'
                        ? Icons.admin_panel_settings_outlined
                        : Icons.shield_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                      child: const Text(
                        'Add',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    ctrl.dispose();
    if (shortId == null || shortId.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).addStaffByShortId(
            masterLeagueId: widget.masterLeagueId,
            shortId: shortId,
            role: role,
          );
      _snack('${role == 'admin' ? 'Admin' : 'Moderator'} added');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTemplateComposer(MasterLeague ml) async {
    if (!_isOwner(ml)) {
      _snack('Only the owner can create templates.', error: true);
      return;
    }

    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    LeagueFormat format = LeagueFormat.classic;
    LeaguePrivacy privacy = LeaguePrivacy.private;
    bool homeAwayEnabled = false;
    bool containsRewards = false;
    int maxTeams = 20;

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            List<int> allowedTeams() {
              switch (format) {
                case LeagueFormat.uclGroup:
                  return const [16, 32];
                case LeagueFormat.uclSwiss:
                  return const [18, 36];
                case LeagueFormat.classic:
                default:
                  return const [20];
              }
            }

            if (!allowedTeams().contains(maxTeams)) {
              maxTeams = allowedTeams().first;
            }

            final supportsHomeAway = format == LeagueFormat.classic ||
                format == LeagueFormat.uclGroup;
            if (!supportsHomeAway) {
              homeAwayEnabled = false;
            }

            return AlertDialog(
              title: const Text('Create Competition Template'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Template Name',
                        prefixIcon: Icon(Icons.bookmark_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Template Description',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<LeagueFormat>(
                      value: format,
                      decoration: const InputDecoration(
                        labelText: 'Competition Format',
                        prefixIcon: Icon(Icons.auto_awesome_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: LeagueFormat.classic,
                          child: Text('Classic League'),
                        ),
                        DropdownMenuItem(
                          value: LeagueFormat.uclGroup,
                          child: Text('UCL Group League'),
                        ),
                        DropdownMenuItem(
                          value: LeagueFormat.uclSwiss,
                          child: Text('Swiss / Series League'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() {
                          format = v;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: maxTeams,
                      decoration: const InputDecoration(
                        labelText: 'Max Teams',
                        prefixIcon: Icon(Icons.groups_outlined),
                      ),
                      items: allowedTeams()
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e,
                              child: Text('$e teams'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => maxTeams = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<LeaguePrivacy>(
                      value: privacy,
                      decoration: const InputDecoration(
                        labelText: 'Privacy',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: LeaguePrivacy.private,
                          child: Text('Private'),
                        ),
                        DropdownMenuItem(
                          value: LeaguePrivacy.public,
                          child: Text('Public'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => privacy = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: containsRewards,
                      onChanged: (v) =>
                          setModalState(() => containsRewards = v),
                      title: const Text('Contains rewards'),
                    ),
                    if (supportsHomeAway)
                      SwitchListTile.adaptive(
                        value: homeAwayEnabled,
                        onChanged: (v) =>
                            setModalState(() => homeAwayEnabled = v),
                        title: const Text('Home & Away matches'),
                        subtitle: const Text(
                          'Each team plays twice (home and away).',
                        ),
                      ),
                    if (format == LeagueFormat.uclSwiss) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: cs.primary.withOpacity(0.08),
                          border: Border.all(
                            color: cs.primary.withOpacity(0.18),
                          ),
                        ),
                        child: const Text(
                          'Swiss / Series templates are ideal for repeat tournament structures.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save Template'),
                ),
              ],
            );
          },
        );
      },
    );

    if (save != true) {
      nameCtrl.dispose();
      descCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    final description = descCtrl.text.trim();
    nameCtrl.dispose();
    descCtrl.dispose();

    if (name.isEmpty) {
      _snack('Template name is required.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final now = DateTime.now().millisecondsSinceEpoch;

      final template = CompetitionTemplate(
        id: '',
        masterLeagueId: ml.id,
        name: name,
        description: description,
        format: format,
        privacy: privacy,
        maxTeams: maxTeams,
        homeAwayEnabled: homeAwayEnabled,
        containsRewards: containsRewards,
        createdAtMs: now,
        updatedAtMs: now,
        createdBy: _currentUid,
      );

      await repo.saveCompetitionTemplate(
        masterLeagueId: ml.id,
        template: template,
      );

      _snack('Competition template saved.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteTemplate(
    MasterLeague ml,
    CompetitionTemplate template,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete template?',
          style: TextStyle(color: cs.error),
        ),
        content: Text('Delete "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).deleteCompetitionTemplate(
            masterLeagueId: ml.id,
            templateId: template.id,
          );
      _snack('Template deleted.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteWorkspace(MasterLeague master) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final confirmationName = master.name.trim().isNotEmpty
        ? master.name.trim()
        : await _ownerDisplayName(master.ownerId);

    final ctrl = TextEditingController();
    String typed = '';
    bool deleting = false;
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !deleting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final matches = typed.trim() == confirmationName;
            final showMismatch = typed.isNotEmpty && !matches;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Glass(
                borderRadius: 30,
                padding: const EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: cs.error.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cs.error.withOpacity(0.28),
                              ),
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: cs.error,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Delete Workspace',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.error.withOpacity(0.22),
                          ),
                        ),
                        child: Text(
                          '⚠️ This action will permanently delete your workspace, including all leagues, players, and data. This cannot be undone.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w900,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Please type your profile name exactly to confirm.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.78),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.primary.withOpacity(0.18),
                          ),
                        ),
                        child: SelectableText(
                          confirmationName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        enabled: !deleting,
                        onChanged: (value) {
                          setModalState(() {
                            typed = value;
                            errorText = showMismatch ? 'Name does not match' : null;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Type exact name to confirm',
                          prefixIcon: const Icon(Icons.edit_outlined),
                          errorText: showMismatch ? 'Name does not match' : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: deleting
                                  ? null
                                  : () => Navigator.of(ctx).pop(false),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: (!matches || deleting)
                                  ? null
                                  : () async {
                                      setModalState(() => deleting = true);
                                      Navigator.of(ctx).pop(true);
                                    },
                              child: Text(
                                deleting ? 'Deleting...' : 'Delete Workspace',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    ctrl.dispose();

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).delete(master.id);
      if (!mounted) return;
      _snack('Workspace deleted.');
      context.go('/master-leagues');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useCompetitionTemplate(CompetitionTemplate template) {
    context.push('/leagues/create', extra: <String, dynamic>{
      'masterLeagueId': widget.masterLeagueId.trim(),
      'initialFormat': template.format,
      'type': template.format == LeagueFormat.classic
          ? 'classic'
          : (template.format == LeagueFormat.uclSwiss ? 'swiss' : 'ucl'),
      'maxTeams': template.maxTeams,
      'templateId': template.id,
      'templateName': template.name,
      'templateDescription': template.description,
      'privacy': template.privacy.name,
      'homeAwayEnabled': template.homeAwayEnabled,
      'containsRewards': template.containsRewards,
    });
  }

  void _openOrganizerProfile(MasterLeague master) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrganizerProfileScreen(masterLeagueId: master.id),
      ),
    );
  }

  Future<void> _showOwnerMenu(MasterLeague master) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename Master League'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Organizer Profile'),
              onTap: () => Navigator.of(ctx).pop('profile'),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Add Admin'),
              onTap: () => Navigator.of(ctx).pop('admin'),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Add Moderator'),
              onTap: () => Navigator.of(ctx).pop('moderator'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Delete Workspace'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'rename':
        await _showRenameDialog(master);
        break;
      case 'profile':
        _openOrganizerProfile(master);
        break;
      case 'admin':
        await _showAddStaffDialog(role: 'admin');
        break;
      case 'moderator':
        await _showAddStaffDialog(role: 'moderator');
        break;
      case 'delete':
        await _confirmDeleteWorkspace(master);
        break;
    }
  }

  Future<void> _showAllCompetitionsSheet(
    MasterLeague master,
    List<League> leagues,
    ThemeData theme,
    ColorScheme cs,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Glass(
              borderRadius: 28,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events_outlined, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All Competitions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${leagues.length}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: leagues.isEmpty
                          ? const Center(
                              child: EmptyState(
                                title: 'No competitions yet',
                                message:
                                    'There are no competitions in this Master League.',
                                icon: Icons.emoji_events_outlined,
                              ),
                            )
                          : ListView.separated(
                              itemCount: leagues.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final l = leagues[index];
                                return FutureBuilder<Membership?>(
                                  future: _membershipForLeague(l.id),
                                  builder: (context, membershipSnap) {
                                    final joined = membershipSnap.data != null;
                                    final joiningThis = _joiningLeagueId == l.id;

                                    return Glass(
                                      borderRadius: 22,
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            height: 230,
                                            child: LeagueFlipCard(
                                              league: l,
                                              leagueId: l.id,
                                              leagueName: l.name,
                                              leagueCode: l.code,
                                              distribution:
                                                  '${l.format.displayName} • ${l.season}',
                                              subtitle: l.region,
                                              imageUrl: l.leagueImageUrl,
                                              isOwner: _currentUid.isNotEmpty &&
                                                  l.organizerUid.trim() ==
                                                      _currentUid,
                                              onDoubleTap: () =>
                                                  context.push('/leagues/${l.id}'),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      context.push('/leagues/${l.id}'),
                                                  icon: const Icon(
                                                    Icons.open_in_new_rounded,
                                                  ),
                                                  label: const Text(
                                                    'Open',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: joined
                                                    ? FilledButton.tonalIcon(
                                                        onPressed: null,
                                                        icon: const Icon(
                                                          Icons
                                                              .check_circle_outline_rounded,
                                                        ),
                                                        label: const Text(
                                                          'Joined',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w900,
                                                          ),
                                                        ),
                                                      )
                                                    : FilledButton.icon(
                                                        onPressed: joiningThis
                                                            ? null
                                                            : () => _promptJoinCompetition(l),
                                                        icon: joiningThis
                                                            ? const SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth: 2,
                                                                  color:
                                                                      Colors.white,
                                                                ),
                                                              )
                                                            : const Icon(
                                                                Icons.login_rounded),
                                                        label: Text(
                                                          joiningThis
                                                              ? 'Joining...'
                                                              : 'Join',
                                                          style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w900,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompetitionTemplatesSection(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    if (!_isOwner(master)) return const SizedBox.shrink();

    final templatesAsync =
        ref.watch(masterLeagueCompetitionTemplatesProvider(master.id));

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Competition Templates',
            padding: EdgeInsets.zero,
            trailing: TextButton.icon(
              onPressed: () => _showTemplateComposer(master),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'New',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Save reusable competition setups and launch faster next time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.68),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          templatesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              '$e',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w800,
              ),
            ),
            data: (templates) {
              if (templates.isEmpty) {
                return Text(
                  'No templates yet. Save your first reusable competition setup.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return Column(
                children: templates.map((template) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Glass(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  template.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete template',
                                onPressed: () =>
                                    _confirmDeleteTemplate(master, template),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          if (template.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              template.description.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.76),
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _templateChip(
                                cs,
                                icon: Icons.auto_awesome_outlined,
                                label: template.format.displayName,
                              ),
                              _templateChip(
                                cs,
                                icon: Icons.groups_outlined,
                                label: '${template.maxTeams} teams',
                              ),
                              _templateChip(
                                cs,
                                icon: Icons.lock_outline,
                                label: template.privacy.name == 'private'
                                    ? 'Private'
                                    : 'Public',
                              ),
                              if (template.homeAwayEnabled)
                                _templateChip(
                                  cs,
                                  icon: Icons.swap_horiz,
                                  label: 'Home & Away',
                                ),
                              if (template.containsRewards)
                                _templateChip(
                                  cs,
                                  icon: Icons.card_giftcard_outlined,
                                  label: 'Rewards',
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: () => _useCompetitionTemplate(template),
                              icon: const Icon(Icons.bolt_rounded),
                              label: const Text(
                                'Use Template',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _templateChip(
    ColorScheme cs, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerQuickActions(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
      required Color tint,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withOpacity(0.12),
                  border: Border.all(color: tint.withOpacity(0.26)),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.62),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurface.withOpacity(0.34),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        tile(
          icon: Icons.badge_outlined,
          title: 'Organizer Profile',
          subtitle: 'Branding, socials, bio, and public identity',
          onTap: () => _openOrganizerProfile(master),
          tint: cs.primary,
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.campaign_outlined,
          title: 'Organizer Announcements',
          subtitle:
              'Post updates for competitions, registration, and important notices',
          onTap: () => _showAnnouncementComposer(master),
          tint: const Color(0xFF8B5CF6),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.forum_outlined,
          title: 'Organizer Chat',
          subtitle:
              'General community chat across this organizer’s competitions',
          onTap: () => context.push('/master-leagues/${master.id}/chat'),
          tint: const Color(0xFF0EA5E9),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.gavel_rounded,
          title: 'Organizer Discipline',
          subtitle:
              'Warnings, point deductions, and organizer chat sanctions',
          onTap: () => context.push('/master-leagues/${master.id}/discipline'),
          tint: const Color(0xFFDC2626),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.bookmarks_outlined,
          title: 'Competition Templates',
          subtitle: 'Save reusable competition setups and launch faster',
          onTap: null,
          tint: const Color(0xFF14B8A6),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.add_circle_outline_rounded,
          title: 'Create Competition',
          subtitle: 'Launch a new competition inside this workspace',
          onTap: () => _showCreateCompetitionSheet(context, master),
          tint: const Color(0xFF22C55E),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.delete_forever_outlined,
          title: 'Delete Workspace',
          subtitle:
              'Permanently remove this organizer workspace and all linked data',
          onTap: () => _confirmDeleteWorkspace(master),
          tint: cs.error,
        ),
      ],
    );
  }

  Widget _buildVisitorOverview(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final followStateAsync =
        ref.watch(masterLeagueFollowStateProvider(master.id));
    final followersCountAsync =
        ref.watch(masterLeagueFollowersCountProvider(master.id));

    final statusColor = master.isVerifiedOrganizer
        ? const Color(0xFF1D9BF0)
        : (master.isVerificationPending
            ? const Color(0xFFF59E0B)
            : cs.onSurface.withOpacity(0.60));

    final statusText = master.isVerifiedOrganizer
        ? 'Verified Organizer'
        : (master.isVerificationPending
            ? 'Verification Pending'
            : 'Unverified Organizer');

    Widget item({
      required IconData icon,
      required String label,
      required String value,
      required Color tint,
    }) {
      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withOpacity(0.12),
                border: Border.all(color: tint.withOpacity(0.24)),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.68),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Organizer Overview',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.visibility_outlined, color: cs.primary),
          ),
          const SizedBox(height: 10),
          item(
            icon: Icons.verified_user_outlined,
            label: 'Organizer Status',
            value: statusText,
            tint: statusColor,
          ),
          const SizedBox(height: 10),
          item(
            icon: Icons.favorite_border_rounded,
            label: 'Followers',
            value: followersCountAsync.maybeWhen(
              data: (v) => '$v',
              orElse: () => '${master.followersCount}',
            ),
            tint: const Color(0xFFEF4444),
          ),
          const SizedBox(height: 10),
          item(
            icon: Icons.badge_outlined,
            label: 'Profile Access',
            value: 'View Organizer Profile',
            tint: cs.primary,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openOrganizerProfile(master),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text(
                    'View Organizer Profile',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => context.push('/master-leagues/${master.id}/chat'),
              icon: const Icon(Icons.forum_outlined),
              label: const Text(
                'Organizer Chat',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          followStateAsync.when(
            loading: () => const SizedBox(
              width: double.infinity,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ),
            ),
            error: (_, __) => SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _followBusy ? null : () => _toggleFollow(master),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text(
                  'Follow Organizer',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            data: (isFollowing) {
              return SizedBox(
                width: double.infinity,
                child: isFollowing
                    ? FilledButton.tonalIcon(
                        onPressed: _followBusy ? null : () => _toggleFollow(master),
                        icon: _followBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          _followBusy ? 'Please wait...' : 'Following',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _followBusy ? null : () => _toggleFollow(master),
                        icon: _followBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          _followBusy ? 'Please wait...' : 'Follow Organizer',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAnnouncementSection(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return StreamBuilder<LeagueAnnouncement?>(
      stream: _watchPinnedWorkspaceAnnouncement(master.id),
      builder: (context, snap) {
        final pinned = snap.data;
        if (pinned == null) return const SizedBox.shrink();

        return Glass(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Pinned Organizer Notice',
                padding: EdgeInsets.zero,
                trailing: Icon(Icons.push_pin_rounded, color: cs.primary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pinned.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_isOwner(master))
                    TextButton.icon(
                      onPressed: () => _unpinAnnouncement(pinned),
                      icon: const Icon(Icons.push_pin_outlined, size: 18),
                      label: const Text(
                        'Unpin',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pinned.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.82),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _announcementMetaChip(
                    cs,
                    icon: Icons.person_outline_rounded,
                    label: pinned.authorName.trim().isEmpty
                        ? 'Organizer'
                        : pinned.authorName.trim(),
                  ),
                  _announcementMetaChip(
                    cs,
                    icon: Icons.schedule_rounded,
                    label: pinned.pinnedAtMs > 0
                        ? DateTime.fromMillisecondsSinceEpoch(
                                pinned.pinnedAtMs,
                              )
                            .toLocal()
                            .toString()
                            .split('.')
                            .first
                        : 'Pinned',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnnouncementsSection(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return StreamBuilder<List<LeagueAnnouncement>>(
      stream: _watchWorkspaceAnnouncements(master.id),
      builder: (context, snap) {
        final announcements = snap.data ?? const <LeagueAnnouncement>[];

        return Glass(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Organizer Announcements',
                padding: EdgeInsets.zero,
                trailing: _isOwner(master)
                    ? TextButton.icon(
                        onPressed: () => _showAnnouncementComposer(master),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Post',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      )
                    : Icon(Icons.campaign_outlined, color: cs.primary),
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting &&
                  announcements.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (announcements.isEmpty)
                Text(
                  'No organizer announcements yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...announcements.take(6).map((ann) {
                  final isMyAnnouncement = ann.authorId.trim().isNotEmpty &&
                      ann.authorId.trim() == _currentUid;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Glass(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ann.pinned) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  color: cs.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Pinned',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ann.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              if (_isOwner(master)) ...[
                                if (ann.pinned)
                                  IconButton(
                                    tooltip: 'Unpin announcement',
                                    onPressed: () => _unpinAnnouncement(ann),
                                    icon: Icon(
                                      Icons.push_pin_outlined,
                                      color: cs.primary,
                                      size: 20,
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Pin announcement',
                                    onPressed: () => _pinAnnouncement(ann),
                                    icon: Icon(
                                      Icons.push_pin_rounded,
                                      color: cs.primary,
                                      size: 20,
                                    ),
                                  ),
                              ],
                              if (_isOwner(master) || isMyAnnouncement)
                                IconButton(
                                  tooltip: 'Delete announcement',
                                  onPressed: () => _confirmDeleteAnnouncement(ann),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: cs.error,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ann.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.78),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _announcementMetaChip(
                                cs,
                                icon: Icons.person_outline_rounded,
                                label: ann.authorName.trim().isEmpty
                                    ? 'Organizer'
                                    : ann.authorName.trim(),
                              ),
                              _announcementMetaChip(
                                cs,
                                icon: Icons.schedule_rounded,
                                label: ann.createdAtMs > 0
                                    ? DateTime.fromMillisecondsSinceEpoch(
                                            ann.createdAtMs,
                                          )
                                        .toLocal()
                                        .toString()
                                        .split('.')
                                        .first
                                    : 'Unknown time',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
            ],
          ),
        );
      },
    );
  }

  Widget _announcementMetaChip(
    ColorScheme cs, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitionsSection(
    MasterLeague master,
    List<League> leagues,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final preview = leagues.isNotEmpty ? leagues.first : null;
    final remaining = leagues.length > 1 ? leagues.length - 1 : 0;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Competitions',
            padding: EdgeInsets.zero,
            trailing: _isOwner(master)
                ? TextButton.icon(
                    onPressed: () => _showCreateCompetitionSheet(context, master),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'Create',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            'Users can join using the invite code or QR on the competition card.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.68),
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          if (preview == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EmptyState(
                  title: 'No competitions yet',
                  message: 'There are no competitions available right now.',
                  icon: Icons.emoji_events_rounded,
                ),
                if (_isOwner(master)) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showCreateCompetitionSheet(context, master),
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Create Competition',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ],
            )
          else
            FutureBuilder<Membership?>(
              future: _membershipForLeague(preview.id),
              builder: (context, membershipSnap) {
                final joined = membershipSnap.data != null;
                final joiningThis = _joiningLeagueId == preview.id;

                return Column(
                  children: [
                    SizedBox(
                      height: 236,
                      child: LeagueFlipCard(
                        league: preview,
                        leagueId: preview.id,
                        leagueName: preview.name,
                        leagueCode: preview.code,
                        distribution:
                            '${preview.format.displayName} • ${preview.season}',
                        subtitle: preview.region,
                        imageUrl: preview.leagueImageUrl,
                        isOwner: _currentUid.isNotEmpty &&
                            preview.organizerUid.trim() == _currentUid,
                        onDoubleTap: () => context.push('/leagues/${preview.id}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/leagues/${preview.id}'),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text(
                              'Open Competition',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: joined
                          ? FilledButton.tonalIcon(
                              onPressed: null,
                              icon: const Icon(Icons.check_circle_outline_rounded),
                              label: const Text(
                                'Already Joined',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: joiningThis
                                  ? null
                                  : () => _promptJoinCompetition(preview),
                              icon: joiningThis
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                joiningThis ? 'Joining...' : 'Join Competition',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                    ),
                    if (remaining > 0) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showAllCompetitionsSheet(
                            master,
                            leagues,
                            theme,
                            cs,
                          ),
                          icon: const Icon(Icons.view_carousel_outlined),
                          label: Text(
                            remaining == 1
                                ? 'View 1 more competition'
                                : 'View $remaining more competitions',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceHero(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final trustColor = master.isVerifiedOrganizer
        ? const Color(0xFF1D9BF0)
        : (master.isVerificationPending
            ? const Color(0xFFF59E0B)
            : cs.onSurface.withOpacity(0.60));

    final trustLabel = master.isVerifiedOrganizer
        ? 'Verified Organizer'
        : (master.isVerificationPending ? 'Verification Pending' : 'Unverified');

    return FutureBuilder<String>(
      future: _ownerDisplayName(master.ownerId),
      builder: (context, ownerSnap) {
        final ownerName = ownerSnap.data?.trim().isNotEmpty == true
            ? ownerSnap.data!.trim()
            : 'Organizer';

        return Glass(
          borderRadius: 30,
          padding: const EdgeInsets.all(18),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [
                  cs.primary.withOpacity(0.20),
                  cs.secondary.withOpacity(0.08),
                  cs.onSurface.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (master.organizerProfile.bannerUrl.trim().isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.network(
                        master.organizerProfile.bannerUrl.trim(),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: cs.onSurface.withOpacity(0.06),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Banner unavailable',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.60),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: cs.primary.withOpacity(0.14),
                        backgroundImage:
                            master.organizerProfile.logoUrl.trim().isNotEmpty
                                ? NetworkImage(
                                    master.organizerProfile.logoUrl.trim(),
                                  )
                                : null,
                        child: master.organizerProfile.logoUrl.trim().isEmpty
                            ? Icon(Icons.hub_rounded, color: cs.primary, size: 30)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  master.name.trim().isEmpty
                                      ? 'Master League'
                                      : master.name.trim(),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                    color: cs.onSurface,
                                  ),
                                ),
                                _heroPill(
                                  text: trustLabel,
                                  color: trustColor,
                                  icon: master.isVerifiedOrganizer
                                      ? Icons.verified_rounded
                                      : (master.isVerificationPending
                                          ? Icons.hourglass_top_rounded
                                          : Icons.shield_outlined),
                                ),
                                if (master.organizerProfile.badge.trim().isNotEmpty)
                                  _heroPill(
                                    text: master.organizerProfile.badge.trim(),
                                    color: const Color(0xFFF59E0B),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Managed by $ownerName',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.68),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              master.organizerProfile.bio.trim().isEmpty
                                  ? 'No organizer bio yet.'
                                  : master.organizerProfile.bio.trim(),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withOpacity(0.82),
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _heroPill({
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(
    MasterLeague master,
    List<League> leagues,
    List<LeagueAnnouncement> announcements,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final followersCountAsync =
        ref.watch(masterLeagueFollowersCountProvider(master.id));

    final stats = <_DashboardStat>[
      _DashboardStat(
        icon: Icons.emoji_events_outlined,
        label: 'Competitions',
        value: '${leagues.length}',
        tint: cs.primary,
      ),
      _DashboardStat(
        icon: Icons.campaign_outlined,
        label: 'Announcements',
        value: '${announcements.length}',
        tint: const Color(0xFF8B5CF6),
      ),
      _DashboardStat(
        icon: Icons.favorite_border_rounded,
        label: 'Followers',
        value: followersCountAsync.maybeWhen(
          data: (v) => '$v',
          orElse: () => '${master.followersCount}',
        ),
        tint: const Color(0xFFEF4444),
      ),
      _DashboardStat(
        icon: master.isVerifiedOrganizer
            ? Icons.verified_rounded
            : (master.isVerificationPending
                ? Icons.hourglass_top_rounded
                : Icons.shield_outlined),
        label: 'Organizer',
        value: master.isVerifiedOrganizer
            ? 'Verified'
            : (master.isVerificationPending ? 'Pending' : 'Public'),
        tint: master.isVerifiedOrganizer
            ? const Color(0xFF1D9BF0)
            : (master.isVerificationPending
                ? const Color(0xFFF59E0B)
                : cs.primary),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: stats.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.1,
      ),
      itemBuilder: (context, index) {
        final item = stats[index];
        return Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.tint.withOpacity(0.12),
                  border: Border.all(color: item.tint.withOpacity(0.24)),
                ),
                child: Icon(item.icon, color: item.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.62),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<MasterLeague?>(
      stream: _watchMasterLeague(widget.masterLeagueId),
      builder: (context, masterSnap) {
        final master = masterSnap.data;
        final isOwner = _isOwner(master);
        final canSeeProfile =
            master != null && master.canSeeOrganizerProfile(_currentUid);

        return GlassScaffold(
          appBar: AppBar(
            title: const Text('Master League Workspace'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (canSeeProfile && master != null)
                IconButton(
                  tooltip: 'Organizer Profile',
                  onPressed: () => _openOrganizerProfile(master),
                  icon: const Icon(Icons.badge_outlined),
                ),
              if (isOwner)
                IconButton(
                  tooltip: 'Create Competition',
                  onPressed: () => _showCreateCompetitionSheet(context, master),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              if (isOwner && master != null)
                IconButton(
                  tooltip: 'Workspace options',
                  onPressed: () => _showOwnerMenu(master),
                  icon: const Icon(Icons.more_vert),
                ),
            ],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: () {
                      if (masterSnap.connectionState == ConnectionState.waiting &&
                          !masterSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (master == null) {
                        return Center(
                          child: EmptyState(
                            title: 'Master League not found',
                            message:
                                'This may have been deleted or you don\'t have access.',
                            icon: Icons.hub_rounded,
                            action: FilledButton.icon(
                              onPressed: () => context.go('/master-leagues'),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Go Back'),
                            ),
                          ),
                        );
                      }

                      return StreamBuilder<List<League>>(
                        stream: _watchCompetitions(widget.masterLeagueId),
                        builder: (context, leaguesSnap) {
                          final leagues = leaguesSnap.data ?? const <League>[];

                          return StreamBuilder<List<LeagueAnnouncement>>(
                            stream: _watchWorkspaceAnnouncements(master.id),
                            builder: (context, announcementsSnap) {
                              final announcements =
                                  announcementsSnap.data ??
                                      const <LeagueAnnouncement>[];

                              return ListView(
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  16,
                                  12,
                                  16,
                                  110,
                                ),
                                children: [
                                  _buildWorkspaceHero(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildStatsGrid(
                                    master,
                                    leagues,
                                    announcements,
                                    theme,
                                    cs,
                                  ),
                                  const SizedBox(height: 16),
                                  if (isOwner)
                                    _buildOwnerQuickActions(master, theme, cs)
                                  else
                                    _buildVisitorOverview(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildPinnedAnnouncementSection(
                                    master,
                                    theme,
                                    cs,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildAnnouncementsSection(
                                    master,
                                    theme,
                                    cs,
                                  ),
                                  if (isOwner) ...[
                                    const SizedBox(height: 16),
                                    _buildCompetitionTemplatesSection(
                                      master,
                                      theme,
                                      cs,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _buildCompetitionsSection(
                                    master,
                                    leagues,
                                    theme,
                                    cs,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    }(),
                  ),
                ),
              ),
              if (_busy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.15),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
          floatingActionButton: isOwner
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreateCompetitionSheet(context, master),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Competition'),
                )
              : null,
        );
      },
    );
  }
}

class _DashboardStat {
  const _DashboardStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
}
