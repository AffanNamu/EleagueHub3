// lib/features/football_hub/presentation/football_team_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/football_api_service.dart';
import '../data/football_follows_repository.dart';
import '../models/football_fixture.dart';
import '../models/football_player.dart';
import '../utils/football_season.dart';
import 'football_player_screen.dart';

class FootballTeamScreen extends StatefulWidget {
  const FootballTeamScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.teamLogoUrl,
  });

  final int teamId;
  final String teamName;
  final String? teamLogoUrl;

  @override
  State<FootballTeamScreen> createState() => _FootballTeamScreenState();
}

class _FootballTeamScreenState extends State<FootballTeamScreen> {
  final _service = FootballApiService();
  final _follows = FootballFollowsRepository();

  late Future<List<FootballFixture>> _nextFuture;
  late Future<List<FootballFixture>> _lastFuture;
  late Future<List<FootballSquadPlayer>> _squadFuture;
  bool? _isFollowing;
  bool _notifyEnabled = true;

  @override
  void initState() {
    super.initState();
    _nextFuture = _service.getFixturesForTeam(teamId: widget.teamId, next: 1);
    _lastFuture = _service.getFixturesForTeam(teamId: widget.teamId, last: 5);
    _squadFuture = _service.getSquad(teamId: widget.teamId);
    _follows.getTeamNotifyEnabled(widget.teamId).then((notifyEnabled) {
      if (!mounted) return;
      setState(() {
        _isFollowing = notifyEnabled != null;
        _notifyEnabled = notifyEnabled ?? true;
      });
    });
  }

  Future<void> _toggleFollow() async {
    final currentlyFollowing = _isFollowing ?? false;
    setState(() => _isFollowing = !currentlyFollowing);
    try {
      if (currentlyFollowing) {
        await _follows.unfollowTeam(widget.teamId);
      } else {
        await _follows.followTeam(
          teamId: widget.teamId,
          name: widget.teamName,
          logoUrl: widget.teamLogoUrl,
          notifyEnabled: _notifyEnabled,
        );
        // Following defaults notifications on -- make sure the OS
        // permission is actually granted, otherwise they'd silently never
        // arrive. A no-op if already granted or already denied by the user.
        unawaited(PushMessagingService.instance.requestNotificationPermission());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFollowing = currentlyFollowing);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(UserFriendlyError.toMessage(e))));
    }
  }

  Future<void> _toggleNotify() async {
    if (!(_isFollowing ?? false)) return;
    final prev = _notifyEnabled;
    final next = !prev;
    setState(() => _notifyEnabled = next);
    try {
      await _follows.setTeamNotifyEnabled(widget.teamId, next);
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifyEnabled = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(UserFriendlyError.toMessage(e))));
    }
  }

  void _openPlayer(FootballSquadPlayer p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FootballPlayerScreen(
          playerId: p.id,
          season: currentFootballSeasonGuess(),
          fallbackName: p.name,
          fallbackPhotoUrl: p.photoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(widget.teamName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                if ((widget.teamLogoUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.teamLogoUrl!,
                      width: 48,
                      height: 48,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48),
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.iconCircleBackground(brightness),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.shield_outlined),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.teamName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                ),
                if (_isFollowing ?? false) ...[
                  IconButton(
                    tooltip: _notifyEnabled
                        ? 'Turn off match notifications for this team'
                        : 'Turn on match notifications for this team',
                    onPressed: _toggleNotify,
                    icon: Icon(
                      _notifyEnabled
                          ? Icons.notifications_active
                          : Icons.notifications_off_outlined,
                      color: _notifyEnabled
                          ? AppTheme.limeAccentDark
                          : AppTheme.secondaryText(brightness),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                OutlinedButton.icon(
                  onPressed: _toggleFollow,
                  icon: Icon((_isFollowing ?? false) ? Icons.check : Icons.add),
                  label: Text((_isFollowing ?? false) ? 'Following' : 'Follow'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Next match',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.secondaryText(brightness)),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<FootballFixture>>(
              future: _nextFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final fixtures = snap.data ?? const [];
                if (fixtures.isEmpty) {
                  return Glass(
                    padding: const EdgeInsets.all(14),
                    child: Text('No upcoming match scheduled.', style: TextStyle(color: AppTheme.secondaryText(brightness))),
                  );
                }
                final f = fixtures.first;
                return Glass(
                  padding: const EdgeInsets.all(14),
                  child: InkWell(
                    onTap: () => context.push('/football/match/${f.id}', extra: f),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${f.homeTeamName} vs ${f.awayTeamName}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(brightness)),
                          ),
                        ),
                        Text(
                          DateFormat('EEE d MMM, HH:mm').format(f.kickoff),
                          style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(brightness)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Last 5',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.secondaryText(brightness)),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<FootballFixture>>(
              future: _lastFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final fixtures = snap.data ?? const [];
                if (fixtures.isEmpty) {
                  return Text('No recent results.', style: TextStyle(color: AppTheme.secondaryText(brightness)));
                }
                return Row(
                  children: fixtures.map((f) => _ResultBadge(fixture: f, teamId: widget.teamId)).toList(growable: false),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Squad',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.secondaryText(brightness)),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<FootballSquadPlayer>>(
              future: _squadFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final squad = snap.data ?? const [];
                if (squad.isEmpty) {
                  return Text('Squad not available.', style: TextStyle(color: AppTheme.secondaryText(brightness)));
                }
                return Column(
                  children: squad
                      .map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Glass(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: InkWell(
                              onTap: () => _openPlayer(p),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppTheme.iconCircleBackground(brightness),
                                    backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                                    child: p.photoUrl.isEmpty ? const Icon(Icons.person, size: 16) : null,
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      p.number != null ? '${p.number}' : '-',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.secondaryText(brightness)),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(brightness)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    p.position,
                                    style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(brightness)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.fixture, required this.teamId});
  final FootballFixture fixture;
  final int teamId;

  @override
  Widget build(BuildContext context) {
    final isHome = fixture.homeTeamId == teamId;
    final ownGoals = isHome ? fixture.homeGoals : fixture.awayGoals;
    final oppGoals = isHome ? fixture.awayGoals : fixture.homeGoals;

    Color color;
    String letter;
    if (ownGoals == null || oppGoals == null) {
      color = Colors.grey;
      letter = '-';
    } else if (ownGoals > oppGoals) {
      color = const Color(0xFF22C55E);
      letter = 'W';
    } else if (ownGoals < oppGoals) {
      color = const Color(0xFFEF4444);
      letter = 'L';
    } else {
      color = const Color(0xFFF59E0B);
      letter = 'D';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: color,
        child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white)),
      ),
    );
  }
}
