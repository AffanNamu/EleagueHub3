import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../leagues/data/league_announcements_firebase.dart';
import '../../leagues/models/enums.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_announcement.dart';
import '../../leagues/models/league_format.dart';
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
      final ownerProfile =
          await UserProfileRepository().fetchByUserId(_currentUid);
      final authorName = ownerProfile?.teamName.trim().isNotEmpty == true
          ? ownerProfile!.teamName.trim()
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

  Future<void> _submitVerificationRequest(MasterLeague ml) async {
    if (!ml.isOwner(_currentUid)) {
      _snack('Only the owner can request verification.', error: true);
      return;
    }
    if (ml.isVerifiedOrganizer) {
      _snack('This organizer is already verified.', error: true);
      return;
    }
    if (ml.isVerificationPending) {
      _snack('A verification request is already pending review.', error: true);
      return;
    }

    final noteCtrl = TextEditingController();
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return AlertDialog(
          title: const Text('Request Organizer Verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A paid verification request will be submitted for manual review. This does not automatically approve the organizer. Admin review is still required.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note for admin review (optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.18)),
                ),
                child: const Text(
                  'Use this only for authentic organizer identities. Fake brand impersonation may be rejected.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Proceed to Payment'),
            ),
          ],
        );
      },
    );

    if (shouldContinue != true) {
      noteCtrl.dispose();
      return;
    }

    setState(() => _busy = true);

    try {
      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      final payment = await paymentSvc.payForOrganizerVerification(
        context: context,
        userId: userId,
        masterLeagueId: ml.id,
        masterLeagueName: ml.name,
      );

      if (!mounted) return;

      if (!payment.success) {
        _snack(
          payment.errorMessage ?? 'Verification payment failed.',
          error: true,
        );
        return;
      }

      await repo.submitVerificationRequest(
        masterLeagueId: ml.id,
        attemptId: payment.attemptId,
        paymentId: payment.paymentId,
        receiptId: payment.receiptId ?? '',
        note: noteCtrl.text.trim(),
      );

      if (!mounted) return;
      _snack('Verification request submitted for review.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      noteCtrl.dispose();
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

    if (newName == null || newName.isEmpty || newName == ml.name.trim()) return;

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

            final supportsHomeAway =
                format == LeagueFormat.classic || format == LeagueFormat.uclGroup;
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
                      onChanged: (v) => setModalState(() => containsRewards = v),
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
                          border: Border.all(color: cs.primary.withOpacity(0.18)),
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

  Widget _buildCompetitionTemplatesSection(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
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
            trailing: _isOwner(master)
                ? TextButton.icon(
                    onPressed: () => _showTemplateComposer(master),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'New',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : Icon(Icons.bookmarks_outlined, color: cs.primary),
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
                  _isOwner(master)
                      ? 'No templates yet. Save your first reusable competition setup.'
                      : 'This organizer has not created competition templates yet.',
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
                              if (_isOwner(master))
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

  Widget _buildAnalyticsPanel(
    MasterLeague master,
    List<League> leagues,
    List<LeagueAnnouncement> announcements,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final totalCompetitions = leagues.length;
    final announcementCount = announcements.length;
    final totalMembers = master.memberIds.length;
    final trustState = master.isVerifiedOrganizer
        ? 'Verified'
        : (master.isVerificationPending ? 'Pending' : 'Unverified');

    final avgMatchesPerCompetition = totalCompetitions == 0
        ? 0.0
        : master.analytics.totalMatches / totalCompetitions;

    final avgTeamsPerCompetition = totalCompetitions == 0
        ? 0.0
        : master.analytics.totalParticipantsTeams / totalCompetitions;

    Widget insightTile({
      required IconData icon,
      required String title,
      required String value,
      required String subtitle,
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
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.72),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.58),
                      fontWeight: FontWeight.w700,
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
            'Workspace Analytics',
            padding: EdgeInsets.zero,
            trailing: Icon(Icons.insights_outlined, color: cs.primary),
          ),
          const SizedBox(height: 10),
          Text(
            'Live organizer insights based on current workspace activity.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.68),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          insightTile(
            icon: Icons.emoji_events_outlined,
            title: 'Competitions',
            value: '$totalCompetitions',
            subtitle: 'Total competitions inside this workspace',
            tint: cs.primary,
          ),
          const SizedBox(height: 10),
          insightTile(
            icon: Icons.campaign_outlined,
            title: 'Announcements',
            value: '$announcementCount',
            subtitle: 'Organizer communication posts',
            tint: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 10),
          insightTile(
            icon: Icons.groups_rounded,
            title: 'Members',
            value: '$totalMembers',
            subtitle: 'Owner + admins + moderators + members',
            tint: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 10),
          insightTile(
            icon: Icons.verified_user_outlined,
            title: 'Trust State',
            value: trustState,
            subtitle: 'Current organizer trust status',
            tint: master.isVerifiedOrganizer
                ? const Color(0xFF1D9BF0)
                : (master.isVerificationPending
                    ? const Color(0xFFF59E0B)
                    : cs.onSurface.withOpacity(0.60)),
          ),
          const SizedBox(height: 10),
          insightTile(
            icon: Icons.sports_score_rounded,
            title: 'Avg Matches / Competition',
            value: avgMatchesPerCompetition.toStringAsFixed(1),
            subtitle: 'Operational depth across competitions',
            tint: const Color(0xFF14B8A6),
          ),
          const SizedBox(height: 10),
          insightTile(
            icon: Icons.group_work_outlined,
            title: 'Avg Teams / Competition',
            value: avgTeamsPerCompetition.toStringAsFixed(1),
            subtitle: 'Participation density estimate',
            tint: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isOwner = _isOwner(master);

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
          subtitle: 'Post updates for competitions, registration, and important notices',
          onTap: isOwner ? () => _showAnnouncementComposer(master) : null,
          tint: const Color(0xFF8B5CF6),
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
          icon: Icons.verified_user_outlined,
          title: master.isVerifiedOrganizer
              ? 'Organizer Verified'
              : (master.isVerificationPending
                  ? 'Verification Pending'
                  : 'Request Verification'),
          subtitle: master.isVerifiedOrganizer
              ? 'This organizer has been reviewed and approved'
              : (master.isVerificationPending
                  ? 'Request already submitted for admin review'
                  : 'Build trust and prevent impersonation scams'),
          onTap: master.isVerifiedOrganizer
              ? null
              : () => _submitVerificationRequest(master),
          tint: master.isVerifiedOrganizer
              ? const Color(0xFF1D9BF0)
              : const Color(0xFFF59E0B),
        ),
        const SizedBox(height: 12),
        tile(
          icon: Icons.add_circle_outline_rounded,
          title: 'Create Competition',
          subtitle: 'Launch a new competition inside this workspace',
          onTap: isOwner ? () => _showCreateCompetitionSheet(context, master) : null,
          tint: const Color(0xFF22C55E),
        ),
      ],
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

  Widget _buildVerificationCard(
    MasterLeague ml,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isOwner = _isOwner(ml);

    Color statusColor;
    String statusText;

    if (ml.isVerifiedOrganizer) {
      statusColor = const Color(0xFF1D9BF0);
      statusText = 'Verified Organizer';
    } else if (ml.isVerificationPending) {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'Verification Pending Review';
    } else if (ml.isVerificationRejected) {
      statusColor = cs.error;
      statusText = 'Verification Rejected';
    } else {
      statusColor = cs.onSurface.withOpacity(0.60);
      statusText = 'Not Verified';
    }

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Verification & Trust',
            trailing: Icon(
              Icons.verified_rounded,
              color: statusColor,
            ),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Text(
            statusText,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ml.isVerifiedOrganizer
                ? 'This organizer has been reviewed and approved. This badge helps participants identify authentic organizers and reduces impersonation scams.'
                : ml.isVerificationPending
                    ? 'A paid verification request has been submitted and is waiting for manual review.'
                    : ml.isVerificationRejected
                        ? 'A verification request was reviewed and rejected. Please contact support or submit again with stronger proof.'
                        : 'This organizer is not yet verified. Verification is designed to help participants trust official organizers.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.78),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (ml.verificationNote.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Review note: ${ml.verificationNote.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (isOwner && !ml.isVerifiedOrganizer && !ml.isVerificationPending) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _submitVerificationRequest(ml),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text(
                'Proceed to Verification Payment',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
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
                  _isOwner(master)
                      ? 'No announcements posted yet. Share your first organizer update.'
                      : 'No organizer announcements yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...announcements.take(6).map((ann) {
                  final isMyAnnouncement =
                      ann.authorId.trim().isNotEmpty &&
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
                                Icon(Icons.push_pin_rounded,
                                    color: cs.primary, size: 18),
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
                                            ann.createdAtMs)
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

  Widget _buildSummaryCard(
    MasterLeague ml,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final draft = ml.initialCompetition;

    Widget infoTile({
      required IconData icon,
      required String label,
      required String value,
      Color? tint,
    }) {
      final c = tint ?? cs.primary;
      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: c, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$label: $value',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Workspace Setup',
          padding: EdgeInsets.zero,
          trailing: Icon(
            Icons.workspace_premium_outlined,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 10),
        infoTile(
          icon: Icons.workspace_premium_outlined,
          label: 'Plan',
          value: ml.plan.displayName,
        ),
        const SizedBox(height: 8),
        infoTile(
          icon: Icons.receipt_long_outlined,
          label: 'Receipt',
          value: ml.sourceReceiptId.isEmpty ? 'Not available' : ml.sourceReceiptId,
        ),
        const SizedBox(height: 8),
        infoTile(
          icon: Icons.payments_outlined,
          label: 'Payment ID',
          value: ml.sourcePaymentId.isEmpty ? 'Not available' : ml.sourcePaymentId,
        ),
        const SizedBox(height: 8),
        infoTile(
          icon: Icons.fingerprint_outlined,
          label: 'Attempt ID',
          value: ml.createdViaAttemptId.isEmpty
              ? 'Not available'
              : ml.createdViaAttemptId,
        ),
        if (draft != null) ...[
          const SizedBox(height: 8),
          infoTile(
            icon: Icons.emoji_events_outlined,
            label: 'Initial Competition',
            value: draft.name,
            tint: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 8),
          infoTile(
            icon: Icons.payments_rounded,
            label: 'Entry Fee',
            value: '${draft.entryFee.toStringAsFixed(2)} ${draft.currency}',
            tint: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 8),
          infoTile(
            icon: Icons.groups_rounded,
            label: 'Max Participants',
            value: '${draft.maxParticipants}',
            tint: const Color(0xFFF59E0B),
          ),
        ],
      ],
    );
  }

  Widget _buildStaffSummary(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    final staffIds = <String>{
      ml.ownerId.trim(),
      ...ml.roles.entries
          .where((e) {
            final r = e.value.trim().toLowerCase();
            return r == 'admin' || r == 'moderator';
          })
          .map((e) => e.key.trim())
          .where((u) => u.isNotEmpty),
    }.toList(growable: false);

    staffIds.sort((a, b) {
      if (a == ml.ownerId.trim()) return -1;
      if (b == ml.ownerId.trim()) return 1;
      return a.compareTo(b);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Staff Overview',
          padding: EdgeInsets.zero,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isOwner(ml))
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                  tooltip: 'Add Admin',
                  onPressed: () => _showAddStaffDialog(role: 'admin'),
                ),
              if (_isOwner(ml))
                IconButton(
                  icon: const Icon(Icons.shield_outlined, size: 20),
                  tooltip: 'Add Moderator',
                  onPressed: () => _showAddStaffDialog(role: 'moderator'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...staffIds.take(6).map((uid) {
          final isMLOwner = uid == ml.ownerId.trim();
          final role = isMLOwner
              ? 'owner'
              : (ml.roles[uid]?.trim().toLowerCase() ?? 'member');

          Color roleColor;
          IconData roleIcon;
          String roleLabel;

          if (role == 'owner') {
            roleColor = cs.primary;
            roleIcon = Icons.star_rounded;
            roleLabel = 'OWNER';
          } else if (role == 'admin') {
            roleColor = const Color(0xFF22C55E);
            roleIcon = Icons.admin_panel_settings_outlined;
            roleLabel = 'ADMIN';
          } else {
            roleColor = const Color(0xFF8B5CF6);
            roleIcon = Icons.shield_outlined;
            roleLabel = 'MOD';
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: roleColor.withOpacity(0.12),
                      border: Border.all(color: roleColor.withOpacity(0.24)),
                    ),
                    child: Icon(roleIcon, size: 18, color: roleColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      uid == _currentUid ? 'You' : uid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: roleColor.withOpacity(0.12),
                      border: Border.all(color: roleColor.withOpacity(0.28)),
                    ),
                    child: Text(
                      roleLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: roleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (staffIds.length > 6)
          Text(
            '+${staffIds.length - 6} more staff members',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }

  Widget _buildMembersSummary(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Members Snapshot',
          padding: EdgeInsets.zero,
          trailing: Icon(
            Icons.group_outlined,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ml.memberIds.take(10).map((uid) {
            final isOwner = uid == ml.ownerId.trim();
            final color = isOwner ? cs.primary : cs.onSurface.withOpacity(0.70);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: color.withOpacity(0.10),
                border: Border.all(color: color.withOpacity(0.18)),
              ),
              child: Text(
                uid == _currentUid ? 'You' : (isOwner ? 'Owner' : uid),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }).toList(),
        ),
        if (ml.memberIds.length > 10) ...[
          const SizedBox(height: 8),
          Text(
            '+${ml.memberIds.length - 10} more members',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompetitionsSection(
    MasterLeague master,
    List<League> leagues,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return Column(
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
        if (leagues.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmptyState(
                title: 'No competitions yet',
                message: master.initialCompetition == null
                    ? 'Create your first competition inside this workspace.'
                    : 'Initial competition draft saved: ${master.initialCompetition!.name}. Build the actual competition now.',
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
          ...List.generate(leagues.length, (i) {
            final l = leagues[i];
            final icon = l.format == LeagueFormat.classic
                ? Icons.emoji_events_outlined
                : (l.format == LeagueFormat.uclSwiss
                    ? Icons.grid_view_rounded
                    : Icons.groups_rounded);

            return Padding(
              padding: EdgeInsets.only(
                bottom: i == leagues.length - 1 ? 0 : 12,
              ),
              child: InkWell(
                onTap: () => context.push('/leagues/${l.id}'),
                borderRadius: BorderRadius.circular(22),
                child: Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.onSurface.withOpacity(0.06),
                          border: Border.all(
                            color: cs.onSurface.withOpacity(0.10),
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: cs.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${l.format.displayName} • ${l.season}',
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
          }),
      ],
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
                                  announcementsSnap.data ?? const <LeagueAnnouncement>[];

                              return ListView(
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                padding:
                                    const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
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
                                  _buildAnalyticsPanel(
                                    master,
                                    leagues,
                                    announcements,
                                    theme,
                                    cs,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildQuickActions(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildPinnedAnnouncementSection(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildVerificationCard(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildAnnouncementsSection(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildCompetitionTemplatesSection(master, theme, cs),
                                  const SizedBox(height: 16),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 6,
                                        child: _buildSummaryCard(master, theme, cs),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 5,
                                        child: _buildStaffSummary(master, theme, cs),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildMembersSummary(master, theme, cs),
                                  const SizedBox(height: 16),
                                  _buildCompetitionsSection(master, leagues, theme, cs),
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
