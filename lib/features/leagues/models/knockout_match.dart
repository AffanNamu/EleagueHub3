import 'enums.dart';

/// Represents a match in the Bracket stage (Play-off, R16, QF, SF, Final, 3rd Place).
///
/// Notes:
/// - For two-legged ties (e.g., Swiss Play-off), use [isSecondLeg] to indicate leg 2.
/// - A single match can end draw; in true knockout resolution a winner may be decided
///   by penalties. Store that in [tiebreakWinnerTeamId] when applicable.
class KnockoutMatch {
  final String id;
  final String leagueId;

  /// e.g. "Play-off", "Round of 16", "Quarter Finals", "Semi Finals", "Final", "3rd Place"
  final String roundName;

  final String? homeTeamId;
  final String? awayTeamId;

  final int? homeScore;
  final int? awayScore;

  final MatchStatus status;

  /// For ties decided by penalties (or other tiebreak), store the winning team id here.
  /// - For single-leg knockouts: required if match is drawn and must produce a winner.
  /// - For two-leg play-offs: typically used on the SECOND leg if aggregate is drawn.
  final String? tiebreakWinnerTeamId;

  /// The ID of the match the winner will advance to.
  final String? nextMatchId;

  /// Where the loser goes (used for 3rd place).
  final String? loserGoesToMatchId;

  /// True if this match is the second leg of a two-legged tie.
  final bool isSecondLeg;

  const KnockoutMatch({
    required this.id,
    required this.leagueId,
    required this.roundName,
    this.homeTeamId,
    this.awayTeamId,
    this.homeScore,
    this.awayScore,
    required this.status,
    this.tiebreakWinnerTeamId,
    this.nextMatchId,
    this.loserGoesToMatchId,
    this.isSecondLeg = false,
  });

  /// A match is finished when status indicates completion AND both scores exist.
  bool get isFinished =>
      (status == MatchStatus.played || status == MatchStatus.completed) &&
      homeScore != null &&
      awayScore != null;

  /// Winner for this single match.
  /// - If scores not decisive, returns [tiebreakWinnerTeamId] (e.g., penalties).
  /// - For a first leg in a two-legged tie, draws are normal and this may be null.
  String? get winnerTeamId {
    if (!isFinished || homeTeamId == null || awayTeamId == null) return null;

    if (homeScore! > awayScore!) return homeTeamId;
    if (awayScore! > homeScore!) return awayTeamId;

    // Draw -> winner only known if decided by penalties/tiebreak.
    return tiebreakWinnerTeamId;
  }

  /// IMPORTANT:
  /// This copyWith supports explicitly setting nullable fields to null.
  ///
  /// Previous implementation used `param ?? this.field`, which made it impossible
  /// to clear fields like [tiebreakWinnerTeamId] (critical for admin edits).
  static const Object _unset = Object();

  KnockoutMatch copyWith({
    String? id,
    String? leagueId,
    String? roundName,
    Object? homeTeamId = _unset,
    Object? awayTeamId = _unset,
    Object? homeScore = _unset,
    Object? awayScore = _unset,
    MatchStatus? status,
    Object? tiebreakWinnerTeamId = _unset,
    Object? nextMatchId = _unset,
    Object? loserGoesToMatchId = _unset,
    bool? isSecondLeg,
  }) {
    return KnockoutMatch(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      roundName: roundName ?? this.roundName,
      homeTeamId: identical(homeTeamId, _unset) ? this.homeTeamId : homeTeamId as String?,
      awayTeamId: identical(awayTeamId, _unset) ? this.awayTeamId : awayTeamId as String?,
      homeScore: identical(homeScore, _unset) ? this.homeScore : homeScore as int?,
      awayScore: identical(awayScore, _unset) ? this.awayScore : awayScore as int?,
      status: status ?? this.status,
      tiebreakWinnerTeamId: identical(tiebreakWinnerTeamId, _unset)
          ? this.tiebreakWinnerTeamId
          : tiebreakWinnerTeamId as String?,
      nextMatchId: identical(nextMatchId, _unset) ? this.nextMatchId : nextMatchId as String?,
      loserGoesToMatchId: identical(loserGoesToMatchId, _unset)
          ? this.loserGoesToMatchId
          : loserGoesToMatchId as String?,
      isSecondLeg: isSecondLeg ?? this.isSecondLeg,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'leagueId': leagueId,
        'roundName': roundName,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'status': status.name,
        'tiebreakWinnerTeamId': tiebreakWinnerTeamId,
        'nextMatchId': nextMatchId,
        'loserGoesToMatchId': loserGoesToMatchId,
        'isSecondLeg': isSecondLeg,
      };

  factory KnockoutMatch.fromJson(Map<String, dynamic> json) {
    return KnockoutMatch(
      id: json['id'] as String,
      leagueId: json['leagueId'] as String,
      roundName: json['roundName'] as String,
      homeTeamId: json['homeTeamId'] as String?,
      awayTeamId: json['awayTeamId'] as String?,
      homeScore: json['homeScore'] as int?,
      awayScore: json['awayScore'] as int?,
      status: MatchStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MatchStatus.scheduled,
      ),
      tiebreakWinnerTeamId: json['tiebreakWinnerTeamId'] as String?,
      nextMatchId: json['nextMatchId'] as String?,
      loserGoesToMatchId: json['loserGoesToMatchId'] as String?,
      isSecondLeg: json['isSecondLeg'] as bool? ?? false,
    );
  }
}
