import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../data/models/reward_model.dart';
import '../../data/services/reward_firestore_service.dart';
import '../widgets/reward_card.dart';
import 'edit_league_rewards_screen.dart';

class LeagueRewardsScreen extends StatefulWidget {
  const LeagueRewardsScreen({
    super.key,
    required this.leagueId,
    this.showAppBar = true,
  });

  final String leagueId;
  final bool showAppBar;

  @override
  State<LeagueRewardsScreen> createState() => _LeagueRewardsScreenState();
}

class _LeagueRewardsScreenState extends State<LeagueRewardsScreen> {
  final RewardFirestoreService _service = RewardFirestoreService();

  Future<bool> _isOrganizer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;

    final leagueSnap = await FirebaseFirestore.instance
        .collection('leagues')
        .doc(widget.leagueId)
        .get();
    final data = leagueSnap.data();
    if (data == null) return false;

    final organizerUid =
        (data['organizerUid'] ?? data['createdBy'] ?? data['ownerUid'] ?? '')
            .toString();
    return organizerUid.isNotEmpty && organizerUid == uid;
  }

  void _openManageRewards() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditLeagueRewardsScreen(leagueId: widget.leagueId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isWide = MediaQuery.of(context).size.width > 600;

    final content = SafeArea(
      top: true,
      child: Padding(
        padding: EdgeInsets.only(top: widget.showAppBar ? kToolbarHeight : 0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 600 : 500),
            child: StreamBuilder<List<RewardModel>>(
              stream: _service.streamRewards(leagueId: widget.leagueId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorState(message: snapshot.error.toString());
                }

                if (!snapshot.hasData) {
                  return const _LoadingState();
                }

                final rewards = snapshot.data ?? const <RewardModel>[];
                if (rewards.isEmpty) {
                  return const _EmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: AppTheme.limeAccentDark,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: rewards.length,
                    itemBuilder: (context, index) {
                      final reward = rewards[index];
                      return RewardCard(reward: reward);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return content;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          'Rewards',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: <Widget>[
          FutureBuilder<bool>(
            future: _isOrganizer(),
            builder: (context, snap) {
              final canManage = snap.data == true;
              if (!canManage) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Manage Rewards',
                onPressed: _openManageRewards,
                icon: Icon(
                  Icons.edit_outlined,
                  color: AppTheme.primaryText(brightness),
                ),
              );
            },
          ),
        ],
      ),
      body: content,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: AppTheme.limeAccentDark,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Glass(
            padding: const EdgeInsets.all(20),
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.card_giftcard_outlined,
                  size: 48,
                  color: AppTheme.limeAccentDark,
                ),
                const SizedBox(height: 16),
                Text(
                  'No rewards available',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check back later for updates.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Glass(
          padding: const EdgeInsets.all(20),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
