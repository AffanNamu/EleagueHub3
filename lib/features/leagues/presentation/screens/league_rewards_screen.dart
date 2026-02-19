import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/color_compat.dart';
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
    final body = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(0xFF0B0F1A),
            Color(0xFF0A1222),
            Color(0xFF071425),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        top: widget.showAppBar ? false : true,
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

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: rewards.length,
              itemBuilder: (context, index) {
                final reward = rewards[index];
                return RewardCard(reward: reward);
              },
            );
          },
        ),
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.2),
        elevation: 0,
        title: const Text('Rewards'),
        actions: <Widget>[
          FutureBuilder<bool>(
            future: _isOrganizer(),
            builder: (context, snap) {
              final canManage = snap.data == true;
              if (!canManage) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Manage Rewards',
                onPressed: _openManageRewards,
                icon: const Icon(Icons.edit_outlined),
              );
            },
          ),
        ],
      ),
      body: body,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.6),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'No rewards available',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for updates.',
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
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
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium
              ?.copyWith(color: Colors.redAccent.withValues(alpha: 0.9)),
        ),
      ),
    );
  }
}
