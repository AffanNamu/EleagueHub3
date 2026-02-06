import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/data/leagues_repository_local.dart' show LeagueJoinMode;
import '../../leagues/domain/models/global_public_league.dart';
import '../../leagues/logic/global_public_league_join_service.dart';
import '../../leagues/logic/global_public_leagues_providers.dart';
import '../../leagues/utils/current_user.dart';

class GlobalLiveLeaguesScreen extends ConsumerStatefulWidget {
  const GlobalLiveLeaguesScreen({super.key});

  @override
  ConsumerState<GlobalLiveLeaguesScreen> createState() => _GlobalLiveLeaguesScreenState();
}

class _GlobalLiveLeaguesScreenState extends ConsumerState<GlobalLiveLeaguesScreen> {
  String? _joiningLeagueId;

  Future<void> _showJoinModeSheet(GlobalPublicLeague item) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (item.isFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This league is finished.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final LeagueJoinMode? selected = await showModalBottomSheet<LeagueJoinMode>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom).add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Join league',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.league.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _JoinModeTile(
                          icon: Icons.sports_soccer,
                          title: 'Join as participant',
                          subtitle: item.isFullComputed
                              ? 'League is currently full for participants. You can still join as a viewer.'
                              : 'Counts towards league capacity and lets you participate.',
                          badge: item.isFullComputed ? 'FULL' : null,
                          badgeColor: item.isFullComputed ? cs.error : cs.primary,
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.participant),
                        ),
                        const SizedBox(height: 10),
                        _JoinModeTile(
                          icon: Icons.visibility_outlined,
                          title: 'Join as viewer',
                          subtitle: 'View league content without taking a participant slot.',
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.viewer),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Cancel'),
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

    if (!mounted || selected == null) return;
    await _join(item, selected);
  }

  Future<void> _join(GlobalPublicLeague item, LeagueJoinMode mode) async {
    if (_joiningLeagueId == item.league.id) return;

    setState(() => _joiningLeagueId = item.league.id);

    try {
      final userId = await CurrentUser.getOrCreateUserId();

      final service = ref.read(globalPublicLeagueJoinServiceProvider);
      final result = await service.joinPublicLeague(
        league: item,
        userId: userId,
        mode: mode,
      );

      if (!mounted) return;

      if (result.status == GlobalPublicLeagueJoinStatus.finished) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This league is finished.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (result.status == GlobalPublicLeagueJoinStatus.privateLeague) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This league is private.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (result.status == GlobalPublicLeagueJoinStatus.full) {
        if (mode == LeagueJoinMode.participant) {
          final joinViewer = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final dTheme = Theme.of(ctx);
              final dCs = dTheme.colorScheme;
              return AlertDialog(
                backgroundColor: dCs.surface,
                title: const Text('League is full'),
                content: const Text('No participant slots left. Do you want to join as a viewer instead?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Join as viewer'),
                  ),
                ],
              );
            },
          );

          if (joinViewer == true) {
            await _join(item, LeagueJoinMode.viewer);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('League is full.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // joined or alreadyJoined -> navigate into league
      if (context.mounted) {
        // Small delay keeps navigation smooth after bottom sheets.
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50)));
        context.push('/leagues/${item.league.id}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Join failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _joiningLeagueId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncLeagues = ref.watch(globalPublicLeaguesStreamProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Global Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: asyncLeagues.when(
              loading: () => Center(child: CircularProgressIndicator(color: cs.primary)),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: cs.error, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load global leagues:\n$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.public, color: cs.primary, size: 44),
                          const SizedBox(height: 12),
                          Text(
                            'No public leagues available right now.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Discover public leagues from the global community.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final joining = _joiningLeagueId == item.league.id;

                    final subtitleParts = <String>[
                      item.league.format.displayName,
                      item.league.season,
                      item.league.region,
                    ];

                    final countLabel = item.registeredCount == null
                        ? 'Capacity: ${item.league.maxTeams}'
                        : 'Capacity: ${item.registeredCount} / ${item.league.maxTeams}';

                    return Glass(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withOpacity(0.16),
                              border: Border.all(color: cs.primary.withOpacity(0.22)),
                            ),
                            child: Icon(Icons.public, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.league.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    if (item.isFinished) ...[
                                      const SizedBox(width: 8),
                                      _Pill(
                                        label: 'FINISHED',
                                        color: cs.onSurface.withOpacity(0.65),
                                        bg: cs.onSurface.withOpacity(0.10),
                                        border: cs.onSurface.withOpacity(0.18),
                                      ),
                                    ] else if (item.isFullComputed) ...[
                                      const SizedBox(width: 8),
                                      _Pill(
                                        label: 'FULL',
                                        color: cs.error,
                                        bg: cs.error.withOpacity(0.12),
                                        border: cs.error.withOpacity(0.30),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitleParts.join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.70),
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  countLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.65),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: (joining || item.isFinished) ? null : () => _showJoinModeSheet(item),
                                    icon: joining
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.login),
                                    label: Text(joining ? 'Joining...' : 'Join'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: items.length,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinModeTile extends StatelessWidget {
  const _JoinModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.onSurface.withOpacity(0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        _Pill(
                          label: badge!,
                          color: badgeColor ?? cs.primary,
                          bg: (badgeColor ?? cs.primary).withOpacity(0.12),
                          border: (badgeColor ?? cs.primary).withOpacity(0.30),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                      height: 1.25,
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
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
