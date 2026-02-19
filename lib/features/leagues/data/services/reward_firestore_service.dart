import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reward_model.dart';

class RewardFirestoreService {
  RewardFirestoreService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _rewardsCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('rewards');
  }

  /// Creates a reward and returns the new rewardId.
  Future<String> createReward({
    required String leagueId,
    required RewardModel reward,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    final doc = _rewardsCol(leagueId).doc();
    await doc.set(
      reward.toFirestoreCreateJson(
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
      ),
      SetOptions(merge: false),
    );
    return doc.id;
  }

  Future<void> updateReward({
    required String leagueId,
    required String rewardId,
    required RewardModel reward,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    await _rewardsCol(leagueId).doc(rewardId).update(reward.toFirestoreUpdateJson());
  }

  Future<void> deleteReward({
    required String leagueId,
    required String rewardId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    await _rewardsCol(leagueId).doc(rewardId).delete();
  }

  Stream<List<RewardModel>> streamRewards({
    required String leagueId,
  }) {
    return _rewardsCol(leagueId).orderBy('position', descending: false).snapshots().map(
          (snapshot) => snapshot.docs
              .map(
                (d) => RewardModel.fromJson(
                  d.data(),
                  id: d.id,
                ),
              )
              .toList(growable: false),
        );
  }

  static final Map<String, _HasRewardsCacheEntry> _hasRewardsCache = <String, _HasRewardsCacheEntry>{};

  /// Fast check to decide whether to show 🏆 Rewards Available badge.
  ///
  /// Uses a short in-memory cache to reduce repeated reads on list screens.
  Future<bool> hasRewards({
    required String leagueId,
    Duration cacheTtl = const Duration(seconds: 30),
  }) async {
    final now = DateTime.now();
    final cacheKey = leagueId;

    final cached = _hasRewardsCache[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) <= cacheTtl) {
      return cached.value;
    }

    final qs = await _rewardsCol(leagueId).limit(1).get();
    final value = qs.docs.isNotEmpty;

    _hasRewardsCache[cacheKey] = _HasRewardsCacheEntry(value: value, cachedAt: now);
    return value;
  }

  static final Map<String, _TopRewardCacheEntry> _topRewardNameCache = <String, _TopRewardCacheEntry>{};

  /// Fetches the top reward name (position ascending, limit 1).
  ///
  /// Safe single read:
  /// leagues/{leagueId}/rewards orderBy(position) limit(1)
  ///
  /// Returns null when no rewards exist.
  ///
  /// Uses a short in-memory cache to reduce repeated reads on list screens.
  Future<String?> fetchTopRewardName({
    required String leagueId,
    Duration cacheTtl = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();
    final cacheKey = leagueId;

    final cached = _topRewardNameCache[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) <= cacheTtl) {
      return cached.name;
    }

    final qs = await _rewardsCol(leagueId).orderBy('position', descending: false).limit(1).get();
    if (qs.docs.isEmpty) {
      _topRewardNameCache[cacheKey] = _TopRewardCacheEntry(name: null, cachedAt: now);
      return null;
    }

    final data = qs.docs.first.data();
    final name = (data['rewardName'] ?? '').toString().trim();
    final normalized = name.isEmpty ? null : name;

    _topRewardNameCache[cacheKey] = _TopRewardCacheEntry(name: normalized, cachedAt: now);
    return normalized;
  }
}

class _HasRewardsCacheEntry {
  _HasRewardsCacheEntry({required this.value, required this.cachedAt});
  final bool value;
  final DateTime cachedAt;
}

class _TopRewardCacheEntry {
  _TopRewardCacheEntry({required this.name, required this.cachedAt});
  final String? name;
  final DateTime cachedAt;
}
