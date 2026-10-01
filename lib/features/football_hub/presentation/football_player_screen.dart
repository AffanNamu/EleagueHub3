// lib/features/football_hub/presentation/football_player_screen.dart

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/football_api_service.dart';
import '../data/football_follows_repository.dart';
import '../models/football_player.dart';

class FootballPlayerScreen extends StatefulWidget {
  const FootballPlayerScreen({
    super.key,
    required this.playerId,
    required this.season,
    this.fallbackName,
    this.fallbackPhotoUrl,
  });

  final int playerId;
  final int season;
  final String? fallbackName;
  final String? fallbackPhotoUrl;

  @override
  State<FootballPlayerScreen> createState() => _FootballPlayerScreenState();
}

class _FootballPlayerScreenState extends State<FootballPlayerScreen> {
  final _service = FootballApiService();
  final _follows = FootballFollowsRepository();
  late Future<FootballPlayerProfile?> _future;
  bool? _isFollowing;

  @override
  void initState() {
    super.initState();
    _future = _service.getPlayer(playerId: widget.playerId, season: widget.season);
    _follows.isFollowingPlayer(widget.playerId).then((v) {
      if (mounted) setState(() => _isFollowing = v);
    });
  }

  Future<void> _toggleFollow(FootballPlayerProfile? profile) async {
    final currentlyFollowing = _isFollowing ?? false;
    setState(() => _isFollowing = !currentlyFollowing);
    try {
      if (currentlyFollowing) {
        await _follows.unfollowPlayer(widget.playerId);
      } else {
        await _follows.followPlayer(
          playerId: widget.playerId,
          name: profile?.name.isNotEmpty == true ? profile!.name : (widget.fallbackName ?? ''),
          photoUrl: profile?.photoUrl.isNotEmpty == true ? profile!.photoUrl : widget.fallbackPhotoUrl,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFollowing = currentlyFollowing);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(widget.fallbackName ?? 'Player'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<FootballPlayerProfile?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snap.data;
            if (snap.hasError || profile == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snap.hasError
                        ? 'Could not load player.\n${snap.error}'
                        : 'No stats available for this player this season.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppTheme.iconCircleBackground(brightness),
                      backgroundImage: profile.photoUrl.isNotEmpty ? NetworkImage(profile.photoUrl) : null,
                      child: profile.photoUrl.isEmpty ? const Icon(Icons.person, size: 32) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryText(brightness),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (profile.primaryPosition.isNotEmpty) profile.primaryPosition,
                              if (profile.nationality.isNotEmpty) profile.nationality,
                              if (profile.age > 0) '${profile.age} yrs',
                            ].join(' · '),
                            style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
                          ),
                          if (profile.primaryTeamName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (profile.primaryTeamLogoUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      profile.primaryTeamLogoUrl,
                                      width: 16,
                                      height: 16,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 16, height: 16),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  profile.primaryTeamName,
                                  style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _toggleFollow(profile),
                  icon: Icon((_isFollowing ?? false) ? Icons.check : Icons.add),
                  label: Text((_isFollowing ?? false) ? 'Following' : 'Follow'),
                ),
                const SizedBox(height: 20),
                Text(
                  '${widget.season} season',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppTheme.secondaryText(brightness),
                  ),
                ),
                const SizedBox(height: 10),
                Glass(
                  padding: const EdgeInsets.all(16),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    children: [
                      _StatTile(label: 'Apps', value: '${profile.appearances}', brightness: brightness),
                      _StatTile(label: 'Goals', value: '${profile.goals}', brightness: brightness),
                      _StatTile(label: 'Assists', value: '${profile.assists}', brightness: brightness),
                      _StatTile(label: 'Yellow', value: '${profile.yellowCards}', brightness: brightness),
                      _StatTile(label: 'Red', value: '${profile.redCards}', brightness: brightness),
                      _StatTile(
                        label: 'Rating',
                        value: profile.averageRating != null ? profile.averageRating!.toStringAsFixed(2) : '-',
                        brightness: brightness,
                      ),
                    ],
                  ),
                ),
                if (profile.heightCm != null || profile.weightKg != null) ...[
                  const SizedBox(height: 20),
                  Glass(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (profile.heightCm != null)
                          _StatTile(label: 'Height', value: '${profile.heightCm} cm', brightness: brightness),
                        if (profile.weightKg != null)
                          _StatTile(label: 'Weight', value: '${profile.weightKg} kg', brightness: brightness),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.brightness});
  final String label;
  final String value;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.primaryText(brightness)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.secondaryText(brightness)),
        ),
      ],
    );
  }
}
