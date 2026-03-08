import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_format.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';

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
          snap.id, (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>());
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
      BuildContext context, MasterLeague? ml) async {
    // Check league limit before showing options
    if (ml != null && _isOwner(ml)) {
      try {
        final repo = ref.read(masterLeaguesRepositoryProvider);
        await repo.checkLeagueLimitOrThrow(widget.masterLeagueId);
      } catch (e) {
        _snack('$e', error: true);
        return;
      }
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
                          Text(title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface)),
                          const SizedBox(height: 3),
                          Text(subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.65),
                                  fontWeight: FontWeight.w700,
                                  height: 1.2)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurface.withOpacity(0.35)),
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
                      Icon(Icons.add_circle_outline_rounded,
                          color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('Create Competition',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                option(
                    icon: Icons.emoji_events_outlined,
                    title: 'Classic League',
                    subtitle: 'Round-robin style competition',
                    format: LeagueFormat.classic,
                    tint: cs.primary),
                option(
                    icon: Icons.grid_view_rounded,
                    title: 'Swiss League',
                    subtitle: 'Swiss/Series format',
                    format: LeagueFormat.uclSwiss,
                    tint: const Color(0xFF8B5CF6)),
                option(
                    icon: Icons.groups_rounded,
                    title: 'UCL Group League',
                    subtitle: 'Group stage competition',
                    format: LeagueFormat.uclGroup,
                    tint: const Color(0xFF22C55E)),
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
      // Pass max teams so league creation can enforce it
      if (ml != null) 'maxTeams': ml.maxTeamsPerLeague,
    });
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
              Text('Rename Master League',
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                decoration: const InputDecoration(
                    labelText: 'New Name',
                    prefixIcon: Icon(Icons.edit_outlined)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(null),
                        child: const Text('Cancel',
                            style: TextStyle(fontWeight: FontWeight.w900)))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(ctrl.text.trim()),
                        child: const Text('Rename',
                            style: TextStyle(fontWeight: FontWeight.w900)))),
              ]),
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
          masterLeagueId: widget.masterLeagueId, newName: newName);
      _snack('Renamed to "$newName"');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAddMemberDialog() async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = TextEditingController();

    final uid = await showDialog<String>(
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
              Text('Add Member',
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text('Enter the user ID of the member.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                decoration: const InputDecoration(
                    labelText: 'User ID',
                    prefixIcon: Icon(Icons.person_add_outlined)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(null),
                        child: const Text('Cancel',
                            style: TextStyle(fontWeight: FontWeight.w900)))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(ctrl.text.trim()),
                        child: const Text('Add',
                            style: TextStyle(fontWeight: FontWeight.w900)))),
              ]),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (uid == null || uid.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).addMember(
          masterLeagueId: widget.masterLeagueId, memberUid: uid);
      _snack('Member added');
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
              title: Text('Remove Member', style: TextStyle(color: cs.error)),
              content: Text('Remove $memberUid from this Master League?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Remove')),
              ],
            ));
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(masterLeaguesRepositoryProvider).removeMember(
          masterLeagueId: widget.masterLeagueId, memberUid: memberUid);
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
              title: Text('Delete "${ml.name}"?',
                  style: TextStyle(color: cs.error)),
              content: const Text(
                  'Competitions inside will be unlinked (not deleted). '
                  'This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete')),
              ],
            ));
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
              title: Text('Delete "${league.name}"?',
                  style: TextStyle(color: cs.error)),
              content: const Text(
                  'All matches, teams and data will be permanently lost.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete')),
              ],
            ));
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () { Navigator.of(ctx).pop(); _showRenameDialog(ml); }),
          ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Add Member'),
              onTap: () { Navigator.of(ctx).pop(); _showAddMemberDialog(); }),
          ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy ID'),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: ml.id));
                _snack('ID copied');
              }),
          const Divider(),
          ListTile(
              leading: Icon(Icons.delete_forever, color: cs.error),
              title: Text('Delete Master League',
                  style: TextStyle(color: cs.error)),
              onTap: () { Navigator.of(ctx).pop(); _confirmDelete(ml); }),
        ]),
      ),
    );
  }

  void _showCompetitionMenu(League league) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/leagues/${league.id}');
              }),
          ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy League ID'),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: league.id));
                _snack('League ID copied');
              }),
          const Divider(),
          ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.error),
              title: Text('Delete Competition',
                  style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteCompetition(league);
              }),
        ]),
      ),
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
          child: Row(children: [
            Expanded(
                child: Text('Members (${ml.memberIds.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: cs.onSurface))),
            if (isOwner)
              IconButton(
                  icon: const Icon(Icons.person_add_outlined, size: 20),
                  tooltip: 'Add Member',
                  onPressed: _showAddMemberDialog),
          ]),
        ),
        ...ml.memberIds.map((uid) {
          final isMe = uid == _currentUid;
          final isMLOwner = uid == ml.ownerId.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              borderRadius: 18,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
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
                      size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isMe ? 'You' : uid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    if (isMLOwner)
                      Text('Owner',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700)),
                  ],
                )),
                if (isOwner && !isMLOwner)
                  IconButton(
                      icon: Icon(Icons.remove_circle_outline,
                          color: cs.error, size: 20),
                      onPressed: () => _confirmRemoveMember(uid)),
              ]),
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

        return GlassScaffold(
          appBar: AppBar(
            title: const Text('Master League'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Create Competition',
                onPressed: () => _showCreateCompetitionSheet(context, master),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          body: Stack(children: [
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
                              label: const Text('Go Back')),
                        ),
                      );
                    }

                    return ListView(
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16, 12, 16, 110),
                      children: [
                        // Header
                        Glass(
                          borderRadius: 28,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.primary.withOpacity(0.12),
                                    border: Border.all(
                                        color: cs.primary.withOpacity(0.25)),
                                  ),
                                  child: Icon(Icons.hub_rounded,
                                      color: cs.primary, size: 22),
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
                                          color: cs.onSurface.withOpacity(0.65),
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
                              ]),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () =>
                                    _showCreateCompetitionSheet(context, master),
                                icon: const Icon(Icons.add),
                                label: const Text('Create Competition',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                        ),

                        // Members
                        _buildMembers(master, theme, cs),

                        // Competitions
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text('Competitions',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                  color: cs.onSurface)),
                        ),

                        StreamBuilder<List<League>>(
                          stream:
                              _watchCompetitions(widget.masterLeagueId),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Glass(
                                borderRadius: 28,
                                padding: const EdgeInsets.all(16),
                                child: Text('${snap.error}',
                                    style: TextStyle(
                                        color: cs.error,
                                        fontWeight: FontWeight.w800)),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(
                                  child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator()));
                            }

                            final leagues = snap.data!;
                            if (leagues.isEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const EmptyState(
                                    title: 'No competitions yet',
                                    message:
                                        'Tap "Create Competition" to add leagues.',
                                    icon: Icons.emoji_events_rounded,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _showCreateCompetitionSheet(
                                            context, master),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create Competition',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              );
                            }

                            return Column(
                              children:
                                  List.generate(leagues.length, (i) {
                                final l = leagues[i];
                                final icon = l.format == LeagueFormat.classic
                                    ? Icons.emoji_events_outlined
                                    : (l.format == LeagueFormat.uclSwiss
                                        ? Icons.grid_view_rounded
                                        : Icons.groups_rounded);

                                return Padding(
                                  padding: EdgeInsets.only(
                                      bottom:
                                          i == leagues.length - 1 ? 0 : 12),
                                  child: InkWell(
                                    onTap: () =>
                                        context.push('/leagues/${l.id}'),
                                    onLongPress: isOwner
                                        ? () => _showCompetitionMenu(l)
                                        : null,
                                    borderRadius: BorderRadius.circular(22),
                                    child: Glass(
                                      borderRadius: 22,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 14),
                                      child: Row(children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: cs.onSurface
                                                .withOpacity(0.06),
                                            border: Border.all(
                                                color: cs.onSurface
                                                    .withOpacity(0.10)),
                                          ),
                                          child: Icon(icon,
                                              color: cs.primary, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(l.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          color:
                                                              cs.onSurface)),
                                              const SizedBox(height: 4),
                                              Text(
                                                  '${l.format.displayName} • ${l.season}',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          color: cs.onSurface
                                                              .withOpacity(
                                                                  0.65),
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          height: 1.2)),
                                            ],
                                          ),
                                        ),
                                        if (isOwner)
                                          IconButton(
                                              icon: Icon(Icons.more_vert,
                                                  color: cs.onSurface
                                                      .withOpacity(0.4),
                                                  size: 20),
                                              onPressed: () =>
                                                  _showCompetitionMenu(l))
                                        else
                                          Icon(Icons.chevron_right_rounded,
                                              color: cs.onSurface
                                                  .withOpacity(0.35)),
                                      ]),
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
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCreateCompetitionSheet(context, master),
            icon: const Icon(Icons.add),
            label: const Text('Create Competition'),
          ),
        );
      },
    );
  }
}
