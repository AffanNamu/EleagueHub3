///leagues/domain/models.dart
import '../models/enums.dart';

/// Organizer match review decision
enum MatchReviewDecision {
  approve,
  reject,
}

/// Domain model representing a match proof review record.
class MatchReview {
  final String leagueId;
  final String matchId;
  final bool approved;
  final String reason;
  final String reviewedBy;
  final DateTime reviewedAt;

  const MatchReview({
    required this.leagueId,
    required this.matchId,
    required this.approved,
    this.reason = '',
    required this.reviewedBy,
    required this.reviewedAt,
  });
}

class Fixture {
  const Fixture({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.scheduledAt,
    required this.status,
    required this.matchId,
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final DateTime scheduledAt;
  final MatchStatus status;
  final String matchId;

  // These getters help UI code that expects `home`/`away`.
  String get home => homeTeam;
  String get away => awayTeam;

  bool get canUploadProof => status == MatchStatus.pendingProof;
  bool get isReviewable => status == MatchStatus.underReview;
}
