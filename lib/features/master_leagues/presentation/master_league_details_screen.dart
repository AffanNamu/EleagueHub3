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

  void _openOrganizerProfile(MasterLeague ml) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrganizerProfileScreen(masterLeagueId: ml.id),
      ),
    );
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

    final selected = await showModalBottomSheet<LeagueFormat>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

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

    if (selected == null || !mounted) return;

    context.push('/leagues/create', extra: <String, dynamic>{
      'masterLeagueId': widget.masterLeagueId.trim(),
      'initialFormat': selected,
      'type': selected == LeagueFormat.classic
          ? 'classic'
          : (selected == LeagueFormat.uclSwiss ? 'swiss' : 'ucl'),
      if (ml.maxTeamsPerLeague > 0) 'maxTeams': ml.maxTeamsPerLeague,
    });
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
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy ID'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(ClipboardData(text: ml.id));
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
      await ref.read(masterLeaguesRepositoryProvider).delete(widget.masterLeagueId);
      if (!mounted) return;
      _snack('Master League deleted');
      context.go('/master-leagues');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCompetitionTemplate(String templateId) async {
    final templates = await ref.read(
      masterLeagueCompetitionTemplatesProvider(widget.masterLeagueId).future,
    );
    final template = templates.where((e) => e.id == templateId).firstOrNull;
    if (template == null) return;

    if (!mounted) return;
    context.push('/leagues/create', extra: <String, dynamic>{
      'masterLeagueId': widget.masterLeagueId.trim(),
      'initialFormat': template.format,
      'type': template.format == LeagueFormat.classic
          ? 'classic'
          : (template.format == LeagueFormat.uclSwiss ? 'swiss' : 'ucl'),
      'templateName': template.name,
      'templateDescription': template.description,
      'templatePrivacy': template.privacy.name,
      'templateHomeAwayEnabled': template.homeAwayEnabled,
      'templateContainsRewards': template.containsRewards,
      'maxTeams': template.maxTeams,
    });
  }

  Widget _buildWorkspaceHero(
    MasterLeague master,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final statsScore = master.analytics.totalTournamentsCreated +
        master.analytics.totalParticipantsTeams +
        master.analytics.totalMatches;

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
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: cs.primary.withOpacity(0.14),
                    backgroundImage:
                        master.logoUrl.trim().isNotEmpty
                            ? NetworkImage(master.logoUrl.trim())
                            : null,
                    child: master.logoUrl.trim().isEmpty
                        ? Icon(Icons.hub_rounded, color: cs.primary, size: 28)
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
                            _statusPill(
                              cs,
                              master.isActive ? 'ACTIVE' : 'INACTIVE',
                              master.isActive
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFF59E0B),
                            ),
                            _statusPill(
                              cs,
                              master.plan.displayName.toUpperCase(),
                              cs.primary,
                            ),
                            if (master.isVerifiedOrganizer)
                              _statusPill(cs, 'VERIFIED', const Color(0xFF1D9BF0)),
                            if (master.isVerificationPending)
                              _statusPill(cs, 'PENDING REVIEW', const Color(0xFFF59E0B)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Organizer workspace for managing competitions, staff, trust, public identity, updates, and analytics.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.72),
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: cs.onSurface.withOpacity(0.05),
                      border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$statsScore',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'workspace score',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.58),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (master.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  master.bio.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.82),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(ColorScheme cs, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildStatsGrid(
    MasterLeague master,
    List<League> leagues,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final stats = <_DashboardStat>[
      _DashboardStat(
        icon: Icons.emoji_events_outlined,
        label: 'Competitions',
        value: '${leagues.length}',
        tint: cs.primary,
      ),
      _DashboardStat(
        icon: Icons.groups_rounded,
        label: 'Members',
        value: '${master.memberIds.length}',
        tint: const Color(0xFF22C55E),
      ),
      _DashboardStat(
        icon: Icons.analytics_outlined,
        label: 'Tournaments',
        value: '${master.analytics.totalTournamentsCreated}',
        tint: const Color(0xFF8B5CF6),
      ),
      _DashboardStat(
        icon: Icons.sports_score_rounded,
        label: 'Matches',
        value: '${master.analytics.totalMatches}',
        tint: const Color(0xFFF59E0B),
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
        childAspectRatio: 1.65,
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

                          return ListView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding:
                                const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
                            children: [
                              _buildWorkspaceHero(master, theme, cs),
                              const SizedBox(height: 16),
                              _buildStatsGrid(master, leagues, theme, cs),
                              const SizedBox(height: 16),
                              const Glass(
                                borderRadius: 24,
                                padding: EdgeInsets.all(16),
                                child: Text('Workspace dashboard active'),
                              ),
                            ],
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
