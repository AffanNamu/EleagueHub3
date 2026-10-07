// lib/features/football_hub/presentation/football_following_tab.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../data/football_follows_repository.dart';
import '../utils/football_season.dart';
import 'football_player_screen.dart';

class FootballFollowingTab extends StatefulWidget {
  const FootballFollowingTab({super.key});

  @override
  State<FootballFollowingTab> createState() => _FootballFollowingTabState();
}

class _FootballFollowingTabState extends State<FootballFollowingTab> with SingleTickerProviderStateMixin {
  final _follows = FootballFollowsRepository();
  late final TabController _subTabController;
  Future<List<FollowedFootballEntity>>? _teamsFuture;
  Future<List<FollowedFootballEntity>>? _playersFuture;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    _reload();
  }

  void _reload() {
    setState(() {
      _teamsFuture = _follows.getFollowedTeams();
      _playersFuture = _follows.getFollowedPlayers();
    });
  }

  Future<void> _toggleTeamNotify(FollowedFootballEntity team) async {
    final teamId = int.tryParse(team.id);
    if (teamId == null) return;

    final next = !team.notifyEnabled;
    try {
      await _follows.setTeamNotifyEnabled(teamId, next);
      if (next) {
        final granted =
            await PushMessagingService.instance.requestNotificationPermission();
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are blocked for this app in system settings.',
              ),
            ),
          );
        }
      }
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(UserFriendlyError.toMessage(e))));
    }
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          labelColor: AppTheme.limeAccentDark,
          unselectedLabelColor: AppTheme.secondaryText(brightness),
          indicatorColor: AppTheme.limeAccentDark,
          tabs: const [
            Tab(text: 'Teams'),
            Tab(text: 'Players'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _FollowedList(
                future: _teamsFuture,
                emptyLabel: 'You are not following any teams yet.\nOpen a team from Matches or Leagues to follow it.',
                onTap: (e) {
                  final id = int.tryParse(e.id);
                  if (id == null) return;
                  context
                      .push('/football/team/$id', extra: {'teamName': e.name, 'teamLogoUrl': e.imageUrl})
                      .then((_) => _reload());
                },
                onToggleNotify: _toggleTeamNotify,
              ),
              _FollowedList(
                future: _playersFuture,
                emptyLabel: 'You are not following any players yet.\nOpen a player from a team squad to follow them.',
                onTap: (e) {
                  final id = int.tryParse(e.id);
                  if (id == null) return;
                  Navigator.of(context)
                      .push(MaterialPageRoute(
                        builder: (_) => FootballPlayerScreen(
                          playerId: id,
                          season: currentFootballSeasonGuess(),
                          fallbackName: e.name,
                          fallbackPhotoUrl: e.imageUrl,
                        ),
                      ))
                      .then((_) => _reload());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FollowedList extends StatelessWidget {
  const _FollowedList({
    required this.future,
    required this.emptyLabel,
    required this.onTap,
    this.onToggleNotify,
  });

  final Future<List<FollowedFootballEntity>>? future;
  final String emptyLabel;
  final void Function(FollowedFootballEntity) onTap;

  /// When given, renders a per-row notification bell (Teams only -- the
  /// Worker's live-score poller has no equivalent push for followed
  /// players, see FollowedFootballEntity's own doc comment).
  final void Function(FollowedFootballEntity)? onToggleNotify;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return FutureBuilder<List<FollowedFootballEntity>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(UserFriendlyError.toMessage(snap.error!), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(brightness))),
            ),
          );
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyLabel, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(brightness))),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final e = items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: InkWell(
                  onTap: () => onTap(e),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.iconCircleBackground(brightness),
                        backgroundImage: (e.imageUrl ?? '').isNotEmpty ? NetworkImage(e.imageUrl!) : null,
                        child: (e.imageUrl ?? '').isEmpty ? const Icon(Icons.shield_outlined, size: 16) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.name,
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(brightness)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onToggleNotify != null)
                        IconButton(
                          tooltip: e.notifyEnabled
                              ? 'Turn off match notifications for this team'
                              : 'Turn on match notifications for this team',
                          onPressed: () => onToggleNotify!(e),
                          icon: Icon(
                            e.notifyEnabled
                                ? Icons.notifications_active
                                : Icons.notifications_off_outlined,
                            color: e.notifyEnabled
                                ? AppTheme.limeAccentDark
                                : AppTheme.secondaryText(brightness),
                            size: 20,
                          ),
                        ),
                      Icon(Icons.chevron_right, color: AppTheme.secondaryText(brightness)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
