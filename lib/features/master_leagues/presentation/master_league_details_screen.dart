import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_format.dart';
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

  void _openOrganizerProfile(MasterLeague ml) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrganizerProfileScreen(masterLeagueId: ml.id),
      ),
    );
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

  Future<void> _confirmRemoveStaffRole(String staffUid) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove staff role?',
          style: TextStyle(color: cs.error),
        ),
        content: Text(
          'Remove admin/moderator privileges from:\n$staffUid',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).removeStaffRole(
            masterLeagueId: widget.masterLeagueId,
            staffUid: staffUid,
          );
      _snack('Staff role removed');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemoveMember(String memberUid) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove Member',
          style: TextStyle(color: cs.error),
        ),
        content: Text('Remove $memberUid from this Master League?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).removeMember(
            masterLeagueId: widget.masterLeagueId,
            memberUid: memberUid,
          );
      _snack('Member removed');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(MasterLeague ml) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete "${ml.name}"?',
          style: TextStyle(color: cs.error),
        ),
        content: const Text(
          'Competitions inside will be unlinked (not deleted). This cannot be undone.',
        ),
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
      await ref
          .read(masterLeaguesRepositoryProvider)
          .delete(widget.masterLeagueId);
      if (!mounted) return;
      _snack('Master League deleted');
      context.go('/master-leagues');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteCompetition(League league) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete "${league.name}"?',
          style: TextStyle(color: cs.error),
        ),
        content: const Text(
          'All matches, teams and data will be permanently lost.',
        ),
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
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(league.id)
          .delete()
          .timeout(const Duration(seconds: 15));
      _snack('"${league.name}" deleted');
    } catch (e) {
      _snack('Could not delete. $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOwnerMenu(MasterLeague ml) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Organizer Profile'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openOrganizerProfile(ml);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenameDialog(ml);
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Add Admin (Short ID)'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showAddStaffDialog(role: 'admin');
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Add Moderator (Short ID)'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showAddStaffDialog(role: 'moderator');
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy ID'),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: ml.id));
                _snack('ID copied');
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever, color: cs.error),
              title: Text(
                'Delete Master League',
                style: TextStyle(color: cs.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(ml);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCompetitionMenu(League league) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/leagues/${league.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy League ID'),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: league.id));
                _snack('League ID copied');
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.error),
              title: Text(
                'Delete Competition',
                style: TextStyle(color: cs.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteCompetition(league);
              },
            ),
          ],
        ),
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
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Creation Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: cs.onSurface,
            ),
          ),
        ),
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

  Widget _buildStaff(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    final isOwner = _isOwner(ml);

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

    Widget roleBadge(String role) {
      final r = role.trim().toLowerCase();
      Color c;
      String label;
      IconData icon;

      if (r == 'owner') {
        c = cs.primary;
        label = 'OWNER';
        icon = Icons.star_rounded;
      } else if (r == 'admin') {
        c = const Color(0xFF22C55E);
        label = 'ADMIN';
        icon = Icons.admin_panel_settings_outlined;
      } else {
        c = const Color(0xFF8B5CF6);
        label = 'MOD';
        icon = Icons.shield_outlined;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: c.withOpacity(0.14),
          border: Border.all(color: c.withOpacity(0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: c,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Staff',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (isOwner) ...[
                IconButton(
                  icon: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                  ),
                  tooltip: 'Add Admin (Short ID)',
                  onPressed: () => _showAddStaffDialog(role: 'admin'),
                ),
                IconButton(
                  icon: const Icon(Icons.shield_outlined, size: 20),
                  tooltip: 'Add Moderator (Short ID)',
                  onPressed: () => _showAddStaffDialog(role: 'moderator'),
                ),
              ],
            ],
          ),
        ),
        ...staffIds.map((uid) {
          final isMe = uid == _currentUid;
          final isMLOwner = uid == ml.ownerId.trim();
          final role = isMLOwner
              ? 'owner'
              : (ml.roles[uid]?.trim().toLowerCase() ?? 'member');

          final shortIdFromOwner = ml.staffShareIds[uid]?.trim() ?? '';
          final canResolveName = isMLOwner || shortIdFromOwner.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.onSurface.withOpacity(0.06),
                    ),
                    child: Icon(
                      role == 'owner'
                          ? Icons.star_rounded
                          : (role == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : Icons.shield_outlined),
                      color: role == 'owner'
                          ? cs.primary
                          : (role == 'admin'
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF8B5CF6)),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: canResolveName
                        ? FutureBuilder<UserProfile?>(
                            future: UserProfileRepository().fetchByUserId(uid),
                            builder: (context, snap) {
                              final profile = snap.data;
                              final name = profile?.teamName.trim() ?? '';
                              final profileShareId =
                                  profile?.shareId.trim() ?? '';

                              final canShowResolvedName = isMLOwner
                                  ? name.isNotEmpty
                                  : (shortIdFromOwner.isNotEmpty &&
                                      shortIdFromOwner == profileShareId &&
                                      name.isNotEmpty);

                              final title = canShowResolvedName
                                  ? (isMe ? '$name (You)' : name)
                                  : (isMe ? 'You' : uid);

                              final shortIdLine = isMLOwner
                                  ? profileShareId
                                  : shortIdFromOwner;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (shortIdLine.isNotEmpty)
                                    Text(
                                      shortIdLine,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.62),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  if (!isMLOwner &&
                                      shortIdFromOwner.isNotEmpty &&
                                      profile != null &&
                                      profileShareId.isNotEmpty &&
                                      profileShareId != shortIdFromOwner)
                                    Text(
                                      'Short ID mismatch',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: cs.error,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                ],
                              );
                            },
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isMe ? 'You' : uid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                'Short ID not added by owner',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.55),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                  roleBadge(role),
                  if (isOwner && role != 'owner') ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: cs.error,
                        size: 20,
                      ),
                      tooltip: 'Remove staff role',
                      onPressed: () => _confirmRemoveStaffRole(uid),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMembers(MasterLeague ml, ThemeData theme, ColorScheme cs) {
    final isOwner = _isOwner(ml);
    if (ml.memberIds.isEmpty && !isOwner) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Members (${ml.memberIds.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: cs.onSurface,
            ),
          ),
        ),
        ...ml.memberIds.map((uid) {
          final isMe = uid == _currentUid;
          final isMLOwner = uid == ml.ownerId.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isMLOwner
                          ? cs.primary.withOpacity(0.12)
                          : cs.onSurface.withOpacity(0.06),
                    ),
                    child: Icon(
                      isMLOwner
                          ? Icons.star_rounded
                          : Icons.person_outline_rounded,
                      color: isMLOwner
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.5),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isMe ? 'You' : uid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (isOwner && !isMLOwner)
                    IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: cs.error,
                        size: 20,
                      ),
                      onPressed: () => _confirmRemoveMember(uid),
                    ),
                ],
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
            title: const Text('Master League'),
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
            ],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
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

                      return ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
                        children: [
                          Glass(
                            borderRadius: 28,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: cs.primary.withOpacity(0.12),
                                        border: Border.all(
                                          color: cs.primary.withOpacity(0.25),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.hub_rounded,
                                        color: cs.primary,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            master.name.trim().isNotEmpty
                                                ? master.name.trim()
                                                : 'Master League',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.3,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${master.plan.displayName} plan • ${master.plan.description}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color:
                                                  cs.onSurface.withOpacity(0.65),
                                              fontWeight: FontWeight.w700,
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isOwner)
                                      IconButton(
                                        icon: const Icon(Icons.more_vert),
                                        tooltip: 'Options',
                                        onPressed: () => _showOwnerMenu(master),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: isOwner
                                            ? () => _showCreateCompetitionSheet(
                                                  context,
                                                  master,
                                                )
                                            : null,
                                        icon: const Icon(Icons.add),
                                        label: const Text(
                                          'Create Competition',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (canSeeProfile) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _openOrganizerProfile(master),
                                          icon: const Icon(Icons.badge_outlined),
                                          label: const Text(
                                            'Organizer Profile',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _buildSummaryCard(master, theme, cs),
                          _buildStaff(master, theme, cs),
                          _buildMembers(master, theme, cs),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 10),
                            child: Text(
                              'Competitions',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          StreamBuilder<List<League>>(
                            stream: _watchCompetitions(widget.masterLeagueId),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Glass(
                                  borderRadius: 28,
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    '${snap.error}',
                                    style: TextStyle(
                                      color: cs.error,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final leagues = snap.data!;
                              if (leagues.isEmpty) {
                                final draft = master.initialCompetition;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    EmptyState(
                                      title: 'No competitions yet',
                                      message: draft == null
                                          ? 'Tap "Create Competition" to add leagues.'
                                          : 'Initial competition draft saved: ${draft.name}. Tap "Create Competition" to build the actual league inside this Master League.',
                                      icon: Icons.emoji_events_rounded,
                                    ),
                                    if (isOwner) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _showCreateCompetitionSheet(
                                          context,
                                          master,
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text(
                                          'Create Competition',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              }

                              return Column(
                                children: List.generate(leagues.length, (i) {
                                  final l = leagues[i];
                                  final icon =
                                      l.format == LeagueFormat.classic
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
                                      onLongPress: isOwner
                                          ? () => _showCompetitionMenu(l)
                                          : null,
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
                                                color: cs.onSurface
                                                    .withOpacity(0.06),
                                                border: Border.all(
                                                  color: cs.onSurface
                                                      .withOpacity(0.10),
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    l.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.titleSmall
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: cs.onSurface,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${l.format.displayName} • ${l.season}',
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: cs.onSurface
                                                          .withOpacity(0.65),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isOwner)
                                              IconButton(
                                                icon: Icon(
                                                  Icons.more_vert,
                                                  color: cs.onSurface
                                                      .withOpacity(0.4),
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _showCompetitionMenu(l),
                                              )
                                            else
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                color: cs.onSurface
                                                    .withOpacity(0.35),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ],
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
