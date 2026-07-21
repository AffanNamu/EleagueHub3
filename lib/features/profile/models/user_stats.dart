import 'package:cloud_firestore/cloud_firestore.dart';

/// Cached aggregate stats. Lives at users/{uid}/stats/summary.
/// Updated incrementally when a match finishes or a follow happens —
/// never recomputed by counting subcollections on profile view.
class UserStats {
  const UserStats({
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsScored,
    required this.goalsConceded,
    required this.trophies,
    required this.followersCount,
    required this.followingCount,
    required this.competitionsJoined,
  });

  final int wins;
  final int draws;
  final int losses;
  final int goalsScored;
  final int goalsConceded;
  final int trophies;
  final int followersCount;
  final int followingCount;
  final int competitionsJoined;

  int get matchesPlayed => wins + draws + losses;
  double get winPercentage => matchesPlayed == 0 ? 0 : (wins / matchesPlayed) * 100;

  factory UserStats.empty() => const UserStats(
        wins: 0,
        draws: 0,
        losses: 0,
        goalsScored: 0,
        goalsConceded: 0,
        trophies: 0,
        followersCount: 0,
        followingCount: 0,
        competitionsJoined: 0,
      );

  factory UserStats.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return UserStats(
      wins: _asInt(map['wins']),
      draws: _asInt(map['draws']),
      losses: _asInt(map['losses']),
      goalsScored: _asInt(map['goalsScored']),
      goalsConceded: _asInt(map['goalsConceded']),
      trophies: _asInt(map['trophies']),
      followersCount: _asInt(map['followersCount']),
      followingCount: _asInt(map['followingCount']),
      competitionsJoined: _asInt(map['competitionsJoined']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
