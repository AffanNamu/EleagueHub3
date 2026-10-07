// lib/features/football_hub/data/football_follows_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Carries an already-safe message, picked up by UserFriendlyError.toMessage
/// via its `message` getter + "*Exception" name -- see that class's doc
/// comment for why a plain StateError here would otherwise be discarded.
class FootballFollowsRepositoryException implements Exception {
  const FootballFollowsRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A followed team/player row, enough to render the Following tab's list
/// without an extra API-Football call per row (name/logo are cached at
/// follow-time). See firestore.rules' football_followed_teams/players for
/// the matching write rules.
class FollowedFootballEntity {
  final String id; // API-Football's team/player id, as a string.
  final String name;
  final String? imageUrl;

  /// Only meaningful for teams -- the Worker's live-score poller
  /// (_pollLiveFixturesAndNotify) only ever queries football_followed_teams,
  /// so there is no equivalent push for followed players today. Defaults to
  /// true, matching every follow doc written before this toggle existed.
  final bool notifyEnabled;

  const FollowedFootballEntity({
    required this.id,
    required this.name,
    this.imageUrl,
    this.notifyEnabled = true,
  });
}

class FootballFollowsRepository {
  FootballFollowsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw const FootballFollowsRepositoryException('Please sign in and try again.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _teamsCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('football_followed_teams');

  CollectionReference<Map<String, dynamic>> _playersCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('football_followed_players');

  Future<bool> isFollowingTeam(int teamId) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return false;
    final doc = await _teamsCol(uid).doc('$teamId').get();
    return doc.exists;
  }

  Future<bool> isFollowingPlayer(int playerId) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return false;
    final doc = await _playersCol(uid).doc('$playerId').get();
    return doc.exists;
  }

  /// Matches the Worker's FOOTBALL_PROVIDER.id (worker/src/index.js) --
  /// stored on every follow doc per the written Football Hub plan's data
  /// model ("Provider IDs must be stored... allows migration to another
  /// provider later").
  static const String _providerId = 'api-football';

  Future<void> followTeam({
    required int teamId,
    required String name,
    String? logoUrl,
    bool notifyEnabled = true,
  }) async {
    final uid = _requireAuthUid();
    await _teamsCol(uid).doc('$teamId').set(<String, dynamic>{
      'teamId': '$teamId',
      'teamName': name,
      if (logoUrl != null && logoUrl.trim().isNotEmpty) 'teamLogoUrl': logoUrl.trim(),
      'notifyEnabled': notifyEnabled,
      'provider': _providerId,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> unfollowTeam(int teamId) async {
    final uid = _requireAuthUid();
    await _teamsCol(uid).doc('$teamId').delete();
  }

  /// Toggles whether goal/kickoff/full-time pushes fire for an
  /// already-followed team, without touching the follow itself. firestore.
  /// rules only permits this exact single-field diff on this doc.
  Future<void> setTeamNotifyEnabled(int teamId, bool enabled) async {
    final uid = _requireAuthUid();
    await _teamsCol(uid).doc('$teamId').update(<String, dynamic>{
      'notifyEnabled': enabled,
    });
  }

  Future<void> followPlayer({required int playerId, required String name, String? photoUrl}) async {
    final uid = _requireAuthUid();
    await _playersCol(uid).doc('$playerId').set(<String, dynamic>{
      'playerId': '$playerId',
      'playerName': name,
      if (photoUrl != null && photoUrl.trim().isNotEmpty) 'playerPhotoUrl': photoUrl.trim(),
      'provider': _providerId,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> unfollowPlayer(int playerId) async {
    final uid = _requireAuthUid();
    await _playersCol(uid).doc('$playerId').delete();
  }

  Future<List<FollowedFootballEntity>> getFollowedTeams() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return const [];
    final snap = await _teamsCol(uid).orderBy('createdAtMs', descending: true).get();
    return snap.docs
        .map((d) => FollowedFootballEntity(
              id: (d.data()['teamId'] ?? d.id).toString(),
              name: (d.data()['teamName'] ?? '').toString(),
              imageUrl: (d.data()['teamLogoUrl'] as String?)?.trim().isNotEmpty == true
                  ? d.data()['teamLogoUrl'] as String
                  : null,
              notifyEnabled: d.data()['notifyEnabled'] as bool? ?? true,
            ))
        .toList(growable: false);
  }

  /// Returns null if not following the team at all; otherwise its current
  /// notifyEnabled (defaulting true for follow docs written before this
  /// field existed, same default used everywhere else in this file).
  Future<bool?> getTeamNotifyEnabled(int teamId) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return null;
    final doc = await _teamsCol(uid).doc('$teamId').get();
    if (!doc.exists) return null;
    return doc.data()?['notifyEnabled'] as bool? ?? true;
  }

  Future<List<FollowedFootballEntity>> getFollowedPlayers() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return const [];
    final snap = await _playersCol(uid).orderBy('createdAtMs', descending: true).get();
    return snap.docs
        .map((d) => FollowedFootballEntity(
              id: (d.data()['playerId'] ?? d.id).toString(),
              name: (d.data()['playerName'] ?? '').toString(),
              imageUrl: (d.data()['playerPhotoUrl'] as String?)?.trim().isNotEmpty == true
                  ? d.data()['playerPhotoUrl'] as String
                  : null,
            ))
        .toList(growable: false);
  }
}
