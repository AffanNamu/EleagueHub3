import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/league_format.dart';
import '../domain/master_league.dart';

class MasterLeagueDetailsScreen extends StatelessWidget {
  const MasterLeagueDetailsScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  Stream<MasterLeague?> _watchMasterLeague(String id) {
    final doc = FirebaseFirestore.instance.collection('master_leagues').doc(id.trim());
    return doc.snapshots(includeMetadataChanges: true).map((snap) {
      if (!snap.exists) return null;
      return MasterLeague.fromMap(
        snap.id,
        (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>(),
      );
    });
  }

  Stream<List<League>> _watchCompetitions(String masterId) {
    // Avoid composite-index requirements by NOT using orderBy. Sort client-side.
    final q = FirebaseFirestore.instance.collection('leagues').where(
          'masterLeagueId',
          isEqualTo: masterId.trim(),
        );

    return q.snapshots(includeMetadataChanges: true).map((snap) {
      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true ? map['id'] : d.id;
        return League.fromRemoteMap(map);
      }).toList(growable: false);

      final sorted = [...list];
      sorted.sort((a, b) => (b.updatedAtMs).compareTo(a.updatedAtMs));
      return sorted;
    });
  }

  Future<void> _showCreateCompetitionSheet(BuildContext context) async {
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    Icon(Icons.chevron_right_rounded, color: cs.onSurface.withOpacity(0.35)),
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

    // Push into existing league creation dashboard with Master League extras.
    context.push(
      '/leagues/create',
      extra: <String, dynamic>{
        'masterLeagueId': masterLeagueId.trim(),
        'initialFormat': selected,
        'type': selected == LeagueFormat.classic
            ? 'classic'
            : (selected == LeagueFormat.uclSwiss ? 'swiss' : 'ucl'),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Master League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Create Competition',
            onPressed: () => _showCreateCompetitionSheet(context),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: StreamBuilder<MasterLeague?>(
              stream: _watchMasterLeague(masterLeagueId),
              builder: (context, masterSnap) {
                final master = masterSnap.data;

                return ListView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 110),
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
                                  border: Border.all(color: cs.primary.withOpacity(0.25)),
                                ),
                                child: Icon(Icons.hub_rounded, color: cs.primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (master?.name.trim().isNotEmpty == true) ? master!.name.trim() : 'Master League',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Create and manage multiple competitions inside one premium system.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.65),
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _showCreateCompetitionSheet(context),
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'Create Competition',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      stream: _watchCompetitions(masterLeagueId),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Glass(
                            borderRadius: 28,
                            child: Text(
                              '${snap.error}',
                              style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
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
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const EmptyState(
                                title: 'No competitions yet',
                                message: 'Tap “Create Competition” to add Classic, Swiss, or UCL Group leagues.',
                                icon: Icons.emoji_events_rounded,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _showCreateCompetitionSheet(context),
                                icon: const Icon(Icons.add),
                                label: const Text(
                                  'Create Competition',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: List.generate(leagues.length, (i) {
                            final l = leagues[i];

                            final fmtLabel = l.format.displayName;
                            final icon = l.format == LeagueFormat.classic
                                ? Icons.emoji_events_outlined
                                : (l.format == LeagueFormat.uclSwiss ? Icons.grid_view_rounded : Icons.groups_rounded);

                            return Padding(
                              padding: EdgeInsets.only(bottom: i == leagues.length - 1 ? 0 : 12),
                              child: InkWell(
                                onTap: () => context.push('/leagues/${l.id}'),
                                borderRadius: BorderRadius.circular(22),
                                child: Glass(
                                  borderRadius: 22,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: cs.onSurface.withOpacity(0.06),
                                          border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                                        ),
                                        child: Icon(icon, color: cs.primary, size: 20),
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
                                              '$fmtLabel • ${l.season}',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.onSurface.withOpacity(0.65),
                                                fontWeight: FontWeight.w700,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: cs.onSurface.withOpacity(0.35)),
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
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateCompetitionSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Create Competition'),
      ),
    );
  }
}
