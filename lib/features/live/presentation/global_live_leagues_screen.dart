import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/domain/models/global_public_league.dart';
import '../../leagues/logic/global_public_leagues_providers.dart';
import '../../leagues/utils/current_user.dart';

class GlobalLiveLeaguesScreen extends ConsumerStatefulWidget {
  const GlobalLiveLeaguesScreen({super.key});

  @override
  ConsumerState<GlobalLiveLeaguesScreen> createState() => _GlobalLiveLeaguesScreenState();
}

class _GlobalLiveLeaguesScreenState extends ConsumerState<GlobalLiveLeaguesScreen> {
  String? _joiningLeagueId;

  Future<void> _join(GlobalPublicLeague item) async {
    if (_joiningLeagueId == item.league.id) return;

    setState(() => _joiningLeagueId = item.league.id);

    try {
      final userId = await CurrentUser.getOrCreateUserId();

      final service = ref.read(globalPublicLeagueJoinServiceProvider);
      final result = await service.joinPublicLeague(
        league: item,
        userId: userId,
      );

      if (!mounted) return;

      if (result.status == GlobalPublicLeagueJoinStatus.full) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('League is full.'),
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

      // Success (or already joined): navigate into the league.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 50)));
      if (context.mounted) {
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
                            'When leagues reach capacity they automatically disappear from this list.',
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
                        ? 'Spots: ${item.league.maxTeams}'
                        : 'Spots: ${item.registeredCount} / ${item.league.maxTeams}';

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
                                Text(
                                  item.league.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
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
                                    onPressed: joining ? null : () => _join(item),
                                    icon: joining
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.login),
                                    label: Text(joining ? 'Joining...' : 'Join league'),
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
