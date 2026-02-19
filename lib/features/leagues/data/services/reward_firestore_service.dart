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
    return _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('rewards');
  }

  // ---------------------------------------------------------------------------
  // createReward
  // ---------------------------------------------------------------------------
  // Rules hasOnly: ['position','rewardName','rewardType','description',
  //                 'imageUrl','createdAt','createdBy']
  // Rules: createdAt == request.time  (FieldValue.serverTimestamp() satisfies this)
  // Rules: createdBy == request.auth.uid
  // ---------------------------------------------------------------------------
  /// Creates a reward and returns the new rewardId.
  Future<String> createReward({
    required String leagueId,
    required RewardModel reward,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    // Build the map with EXACTLY the fields that the Firestore rules allow.
    // hasOnly([position, rewardName, rewardType, description, imageUrl,
    //          createdAt, createdBy])
    // Do NOT add any extra field — hasOnly means any extra field = denied.
    final data = <String, dynamic>{
      'position': reward.position,
      'rewardName': reward.rewardName.trim(),
      'rewardType': RewardModel.normalizeRewardType(reward.rewardType),
      'description': reward.description.trim(),
      'imageUrl': reward.imageUrl.trim(),
      'createdBy': uid,
      // FieldValue.serverTimestamp() satisfies (createdAt == request.time)
      // in Firestore security rules. Do NOT use DateTime.now() here —
      // that would fail the == request.time check.
      'createdAt': FieldValue.serverTimestamp(),
    };

    final doc = _rewardsCol(leagueId).doc();
    await doc.set(data, SetOptions(merge: false));
    return doc.id;
  }

  // ---------------------------------------------------------------------------
  // updateReward
  // ---------------------------------------------------------------------------
  // Rules hasOnly: ['position','rewardName','rewardType','description',
  //                 'imageUrl','createdAt','createdBy','updatedAt','updatedBy']
  // Rules: updatedAt == request.time  (FieldValue.serverTimestamp() satisfies)
  // Rules: updatedBy == request.auth.uid
  // Rules: createdAt stability — if NOT sent in update payload, rule passes
  //        automatically because !('createdAt' in request.resource.data) == true.
  //        We intentionally do NOT send createdAt/createdBy to let them stay
  //        untouched in the existing document.
  // We use .update() not .set() — only the fields we send are written.
  // ---------------------------------------------------------------------------
  Future<void> updateReward({
    required String leagueId,
    required String rewardId,
    required RewardModel reward,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    if (rewardId.trim().isEmpty) {
      throw ArgumentError('rewardId must not be empty for update.');
    }

    // Build the update map with EXACTLY the fields the rules allow for update.
    // We intentionally omit createdAt and createdBy so they remain untouched
    // in Firestore — the stability checks in the rules pass because
    // !('createdAt' in request.resource.data) evaluates to true.
    final data = <String, dynamic>{
      'position': reward.position,
      'rewardName': reward.rewardName.trim(),
      'rewardType': RewardModel.normalizeRewardType(reward.rewardType),
      'description': reward.description.trim(),
      'imageUrl': reward.imageUrl.trim(),
      // updatedAt must be server time — rules check: updatedAt == request.time
      'updatedAt': FieldValue.serverTimestamp(),
      // updatedBy must be current user — rules check: updatedBy == request.auth.uid
      'updatedBy': uid,
    };

    await _rewardsCol(leagueId).doc(rewardId).update(data);
  }

  // ---------------------------------------------------------------------------
  // deleteReward
  // ---------------------------------------------------------------------------
  Future<void> deleteReward({
    required String leagueId,
    required String rewardId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not authenticated');
    }

    if (rewardId.trim().isEmpty) {
      throw ArgumentError('rewardId must not be empty for delete.');
    }

    await _rewardsCol(leagueId).doc(rewardId).delete();
  }

  // ---------------------------------------------------------------------------
  // streamRewards
  // ---------------------------------------------------------------------------
  Stream<List<RewardModel>> streamRewards({
    required String leagueId,
  }) {
    return _rewardsCol(leagueId)
        .orderBy('position', descending: false)
        .snapshots()
        .map(
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

  // ---------------------------------------------------------------------------
  // hasRewards — cached check for badge display
  // ---------------------------------------------------------------------------
  static final Map<String, _HasRewardsCacheEntry> _hasRewardsCache =
      <String, _HasRewardsCacheEntry>{};

  /// Fast check to decide whether to show 🏆 Rewards Available badge.
  /// Uses a short in-memory cache to reduce repeated reads on list screens.
  Future<bool> hasRewards({
    required String leagueId,
    Duration cacheTtl = const Duration(seconds: 30),
  }) async {
    final now = DateTime.now();

    final cached = _hasRewardsCache[leagueId];
    if (cached != null && now.difference(cached.cachedAt) <= cacheTtl) {
      return cached.value;
    }

    final qs = await _rewardsCol(leagueId).limit(1).get();
    final value = qs.docs.isNotEmpty;

    _hasRewardsCache[leagueId] =
        _HasRewardsCacheEntry(value: value, cachedAt: now);
    return value;
  }

  // ---------------------------------------------------------------------------
  // fetchTopRewardName — cached single-read for list screen previews
  // ---------------------------------------------------------------------------
  static final Map<String, _TopRewardCacheEntry> _topRewardNameCache =
      <String, _TopRewardCacheEntry>{};

  /// Fetches the top reward name (position ascending, limit 1).
  /// Returns null when no rewards exist.
  /// Uses a short in-memory cache to reduce repeated reads on list screens.
  Future<String?> fetchTopRewardName({
    required String leagueId,
    Duration cacheTtl = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();

    final cached = _topRewardNameCache[leagueId];
    if (cached != null && now.difference(cached.cachedAt) <= cacheTtl) {
      return cached.name;
    }

    final qs = await _rewardsCol(leagueId)
        .orderBy('position', descending: false)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) {
      _topRewardNameCache[leagueId] =
          _TopRewardCacheEntry(name: null, cachedAt: now);
      return null;
    }

    final data = qs.docs.first.data();
    final name = (data['rewardName'] ?? '').toString().trim();
    final normalized = name.isEmpty ? null : name;

    _topRewardNameCache[leagueId] =
        _TopRewardCacheEntry(name: normalized, cachedAt: now);
    return normalized;
  }
}

// ---------------------------------------------------------------------------
// Cache entry types
// ---------------------------------------------------------------------------

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
