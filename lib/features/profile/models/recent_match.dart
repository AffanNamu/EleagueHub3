//profile/models/recent_match.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchResult { win, draw, loss }

extension MatchResultX on MatchResult {
  String get storageValue {
    switch (this) {
      case MatchResult.win:
        return 'W';
      case MatchResult.draw:
        return 'D';
      case MatchResult.loss:
        return 'L';
    }
  }

  static MatchResult fromStorage(String? raw) {
    switch (raw) {
      case 'W':
        return MatchResult.win;
      case 'L':
        return MatchResult.loss;
      case 'D':
      default:
        return MatchResult.draw;
    }
  }
}

/// A lightweight cache entry mirroring one finished match, written to
/// users/{uid}/recent_matches/{matchId} so the profile screen never has
/// to scan league subcollections to show match history.
class RecentMatch {
  const RecentMatch({
    required this.id,
    required this.leagueId,
    required this.leagueName,
    required this.opponentName,
    required this.result,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.playedAtMs,
  });

  final String id;
  final String leagueId;
  final String leagueName;
  final String opponentName;
  final MatchResult result;
  final int goalsFor;
  final int goalsAgainst;
  final int playedAtMs;

  factory RecentMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return RecentMatch(
      id: doc.id,
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      leagueName: (map['leagueName'] as String? ?? '').trim(),
      opponentName: (map['opponentName'] as String? ?? '').trim(),
      result: MatchResultX.fromStorage(map['result'] as String?),
      goalsFor: _asInt(map['goalsFor']),
      goalsAgainst: _asInt(map['goalsAgainst']),
      playedAtMs: _asInt(map['playedAtMs']),
    );
  }

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'leagueName': leagueName,
        'opponentName': opponentName,
        'result': result.storageValue,
        'goalsFor': goalsFor,
        'goalsAgainst': goalsAgainst,
        'playedAtMs': playedAtMs,
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
