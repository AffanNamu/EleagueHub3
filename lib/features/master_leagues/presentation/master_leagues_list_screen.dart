import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';
import 'widgets/master_league_card.dart';

class MasterLeaguesListScreen extends ConsumerStatefulWidget {
  const MasterLeaguesListScreen({super.key});

  @override
  ConsumerState<MasterLeaguesListScreen> createState() =>
      _MasterLeaguesListScreenState();
}

class _MasterLeaguesListScreenState
    extends ConsumerState<MasterLeaguesListScreen> {
  bool _createdTimedOut = false;
  bool _joinedTimedOut = false;

  Timer? _createdTimer;
  Timer? _joinedTimer;

  @override
  void initState() {
    super.initState();
    _startTimeouts();
  }

  void _startTimeouts() {
    _createdTimer?.cancel();
    _joinedTimer?.cancel();

    _createdTimedOut = false;
    _joinedTimedOut = false;

    _createdTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _createdTimedOut = true);
    });

    _joinedTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _joinedTimedOut = true);
    });
  }

  @override
  void dispose() {
    _createdTimer?.cancel();
    _joinedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final createdAsync = ref.watch(createdMasterLeaguesProvider);
    final joinedAsync = ref.watch(joinedMasterLeaguesProvider);
    final planAsync = ref.watch(organizerProActivePlanProvider);

    Widget sectionTitle(String title, String subtitle) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildMasterLeagueList(List<MasterLeague> items) {
      if (items.isEmpty) {
        return const EmptyState(
          title: 'No Master Leagues yet',
          message:
              'Create your first organizer workspace to manage competitions in one place.',
          icon: Icons.hub_rounded,
        );
      }

      return Column(
        children: List.generate(items.length, (i) {
          final ml = items[i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
            child: MasterLeagueCard(
              masterLeague: ml,
              onTap: () => context.push('/master-leagues/${ml.id}'),
            ),
          );
        }),
      );
    }

    Widget loadingCard() {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    Widget safeMessageCard({
      required String title,
      bool error = false,
    }) {
      return Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(16),
        child: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: error ? cs.error : cs.onSurface.withOpacity(0.82),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    Widget createdSection() {
      return createdAsync.when(
        loading: () {
          if (_createdTimedOut) {
            return const EmptyState(
              title: 'No Master Leagues yet',
              message:
                  'If you have not created any organizer workspace yet, this is normal.',
              icon: Icons.hub_rounded,
            );
          }
          return loadingCard();
        },
        error: (_, __) => const EmptyState(
          title: 'No Master Leagues yet',
          message: 'You have not created any organizer workspace yet.',
          icon: Icons.hub_rounded,
        ),
        data: buildMasterLeagueList,
      );
    }

    Widget joinedSection() {
      return joinedAsync.when(
        loading: () {
          if (_joinedTimedOut) {
            return const EmptyState(
              title: 'No joined workspaces',
              message:
                  'When you are added to an organizer workspace, it will appear here.',
              icon: Icons.groups_outlined,
            );
          }
          return loadingCard();
        },
        error: (_, __) => const EmptyState(
          title: 'No joined workspaces',
          message:
              'When you are added to an organizer workspace, it will appear here.',
          icon: Icons.groups_outlined,
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              title: 'No joined workspaces',
              message:
                  'When you are added to an organizer workspace, it will appear here.',
              icon: Icons.groups_outlined,
            );
          }
          return buildMasterLeagueList(items);
        },
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Master Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Create Master League',
            onPressed: () => context.push('/master-leagues/create'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/master-leagues/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(createdMasterLeaguesProvider);
                ref.invalidate(joinedMasterLeaguesProvider);
                ref.invalidate(organizerProActivePlanProvider);
                _startTimeouts();
                await Future<void>.delayed(const Duration(milliseconds: 250));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
                children: [
                  Glass(
                    borderRadius: 30,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Organizer Workspaces',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create and manage Master Leagues for your organizer brand, competitions, staff, and announcements.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.72),
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        planAsync.when(
                          loading: () => Text(
                            'Checking active plan...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          error: (_, __) => Text(
                            'Unable to verify active plan right now.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          data: (plan) => Text(
                            plan == null
                                ? 'No active Organizer Pro plan detected.'
                                : 'Active plan: ${plan.displayName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: plan == null
                                  ? cs.onSurface.withOpacity(0.68)
                                  : cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  sectionTitle(
                    'Created by You',
                    'Master Leagues you own and manage.',
                  ),
                  createdSection(),

                  const SizedBox(height: 20),

                  sectionTitle(
                    'Joined Workspaces',
                    'Master Leagues where you are a member, admin, or moderator.',
                  ),
                  joinedSection(),

                  const SizedBox(height: 18),
                  safeMessageCard(
                    title:
                        'If you have never created or joined a Master League before, seeing empty sections here is normal.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
