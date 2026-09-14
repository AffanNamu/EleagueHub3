//presentation/master_league_staff_screen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/master_league.dart';
import '../domain/master_league_roles.dart';
import '../logic/master_leagues_providers.dart';

// ---------------------------------------------------------------------------
// Breakpoints — self-contained, matches OrganizerDisciplineScreen
// ---------------------------------------------------------------------------

class _BP {
  static const double desktop = 900;
}

class _StaffRow {
  const _StaffRow({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.competitionScope,
  });

  final String userId;
  final String displayName;
  final MasterLeagueStaffRole role;
  final List<String> competitionScope;
}

class MasterLeagueStaffScreen extends ConsumerStatefulWidget {
  const MasterLeagueStaffScreen({super.key, required this.masterLeagueId});

  final String masterLeagueId;

  @override
  ConsumerState<MasterLeagueStaffScreen> createState() =>
      _MasterLeagueStaffScreenState();
}

class _MasterLeagueStaffScreenState
    extends ConsumerState<MasterLeagueStaffScreen> {
  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  void _safePop() {
    try {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/');
      }
    } catch (_) {
      GoRouter.of(context).go('/');
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(trimmed),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Stream<MasterLeague?> _watchMasterLeague() {
    return FirebaseFirestore.instance
        .collection('master_leagues')
        .doc(widget.masterLeagueId)
        .snapshots()
        .map((snap) => snap.exists ? MasterLeague.fromDoc(snap) : null);
  }

  Future<Map<String, String>> _resolveNames(List<String> uids) async {
    final names = <String, String>{};
    final clean = uids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (clean.isEmpty) return names;

    const chunkSize = 10;
    final firestore = FirebaseFirestore.instance;
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(
        i,
        (i + chunkSize > clean.length) ? clean.length : i + chunkSize,
      );
      try {
        final snap = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final name = (data['teamName'] ??
                  data['displayName'] ??
                  data['name'] ??
                  data['username'] ??
                  '')
              .toString()
              .trim();
          names[d.id] = name;
        }
      } catch (_) {
        // best-effort — missing names fall back to the raw uid in the UI
      }
    }
    return names;
  }

  Future<void> _showAddStaffDialog(MasterLeague master) async {
    final brightness = Theme.of(context).brightness;
    final ctrl = TextEditingController();
    var selectedRole = MasterLeagueStaffRole.competitionManager;

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Glass(
            borderRadius: 28,
            padding: const EdgeInsets.all(16),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add Staff',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the user short id (share id). Example: eS44e35f',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Short ID',
                    prefixIcon: Icon(Icons.person_search_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Role',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MasterLeagueStaffRole.assignable.map((role) {
                    final selected = selectedRole == role;
                    return ChoiceChip(
                      label: Text(
                        role.displayName,
                        style:
                            const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      selected: selected,
                      onSelected: (_) =>
                          setDialogState(() => selectedRole = role),
                      selectedColor: AppTheme.limeAccent,
                      backgroundColor:
                          AppTheme.tabInactiveBackground(brightness),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.darkText
                            : AppTheme.tabInactiveText(brightness),
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w800,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedRole.description,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                ),
                const SizedBox(height: 16),
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
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => Navigator.of(ctx).pop({
                          'shortId': ctrl.text.trim(),
                          'role': selectedRole.storageValue,
                        }),
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
      ),
    );
    ctrl.dispose();

    final shortId = result?['shortId'] ?? '';
    final role = result?['role'] ?? '';
    if (shortId.isEmpty || role.isEmpty) return;

    try {
      await ref.read(masterLeaguesRepositoryProvider).addStaffByShortId(
            masterLeagueId: widget.masterLeagueId,
            shortId: shortId,
            role: role,
          );
      _snack('Staff member added.');
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _confirmRemoveStaff(_StaffRow row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(Theme.of(ctx).brightness),
        surfaceTintColor: Colors.transparent,
        title: const Text('Remove Staff Member'),
        content: Text(
          'Remove ${row.displayName.isNotEmpty ? row.displayName : row.userId} '
          'as ${row.role.displayName}? They will lose their staff access '
          'immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    try {
      await ref.read(masterLeaguesRepositoryProvider).removeStaff(
            masterLeagueId: widget.masterLeagueId,
            targetUid: row.userId,
          );
      _snack('Staff member removed.');
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _safePop,
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<MasterLeague?>(
          stream: _watchMasterLeague(),
          builder: (context, snap) {
            final master = snap.data;
            if (snap.connectionState == ConnectionState.waiting &&
                master == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (master == null) {
              return const EmptyState(
                title: "We couldn't find that workspace",
                message: 'It may have been deleted or renamed.',
                icon: Icons.error_outline_rounded,
              );
            }

            final isOwner = master.isOwner(_currentUid);
            if (!isOwner) {
              return const EmptyState(
                title: 'Owner only',
                message:
                    'Only the workspace owner can view and manage staff.',
                icon: Icons.lock_outline_rounded,
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final hPad = constraints.maxWidth >= _BP.desktop ? 24.0 : 16.0;
                return _buildBody(master, hPad);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(MasterLeague master, double hPad) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final rows = <_StaffRow>[
      _StaffRow(
        userId: master.ownerId,
        displayName: '',
        role: MasterLeagueStaffRole.owner,
        competitionScope: const [],
      ),
      for (final entry in master.roles.entries)
        if (entry.key.trim() != master.ownerId.trim() &&
            MasterLeagueStaffRole.fromStorageValue(entry.value) != null)
          _StaffRow(
            userId: entry.key,
            displayName: '',
            role: MasterLeagueStaffRole.fromStorageValue(entry.value)!,
            competitionScope: master.staffScopes[entry.key] ?? const [],
          ),
    ];

    return FutureBuilder<Map<String, String>>(
      future: _resolveNames(rows.map((r) => r.userId).toList()),
      builder: (context, nameSnap) {
        final names = nameSnap.data ?? const <String, String>{};
        final resolved = rows
            .map((r) => _StaffRow(
                  userId: r.userId,
                  displayName: names[r.userId] ?? '',
                  role: r.role,
                  competitionScope: r.competitionScope,
                ))
            .toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
              children: [
                Glass(
                  borderRadius: 28,
                  padding: const EdgeInsets.all(16),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Workspace Staff',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Delegate competition management, result entry, or '
                        'moderation without sharing full ownership.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.limeAccent,
                            foregroundColor: AppTheme.darkText,
                          ),
                          onPressed: () => _showAddStaffDialog(master),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text(
                            'Add Staff',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...resolved.map((row) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _staffTile(row),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _staffTile(_StaffRow row) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isOwnerRow = row.role == MasterLeagueStaffRole.owner;

    final title = row.displayName.isNotEmpty ? row.displayName : row.userId;
    final subtitleParts = <String>[
      row.role.displayName,
      if (!isOwnerRow && row.competitionScope.isNotEmpty)
        '${row.competitionScope.length} competition(s) only'
      else if (!isOwnerRow)
        'All competitions',
    ];

    final tint = switch (row.role) {
      MasterLeagueStaffRole.owner => AppTheme.limeAccentDark,
      MasterLeagueStaffRole.competitionManager => const Color(0xFF0EA5E9),
      MasterLeagueStaffRole.resultManager => const Color(0xFF8B5CF6),
      MasterLeagueStaffRole.moderator => const Color(0xFFF59E0B),
    };

    final icon = switch (row.role) {
      MasterLeagueStaffRole.owner => Icons.workspace_premium_rounded,
      MasterLeagueStaffRole.competitionManager =>
        Icons.admin_panel_settings_outlined,
      MasterLeagueStaffRole.resultManager => Icons.scoreboard_outlined,
      MasterLeagueStaffRole.moderator => Icons.shield_outlined,
    };

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
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
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitleParts.join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!isOwnerRow)
            IconButton(
              tooltip: 'Remove',
              icon: Icon(
                Icons.person_remove_alt_1_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _confirmRemoveStaff(row),
            ),
        ],
      ),
    );
  }
}
