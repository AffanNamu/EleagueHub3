/// Represents a single row in a league or group table.
///
/// This domain model calculates competitive statistics like
/// Points and Goal Difference based on match results.
class StandingsRow {
  final String teamId;
  final String teamName;

  final int mp; // Matches Played
  final int w; // Wins
  final int d; // Draws
  final int l; // Losses
  final int gf; // Goals For
  final int ga; // Goals Against

  const StandingsRow({
    required this.teamId,
    required this.teamName,
    required this.mp,
    required this.w,
    required this.d,
    required this.l,
    required this.gf,
    required this.ga,
  });

  /// Automatically calculates Goal Difference.
  int get gd => gf - ga;

  /// Automatically calculates total Points (3 for win, 1 for draw).
  int get pts => w * 3 + d;

  StandingsRow copyWith({
    int? mp,
    int? w,
    int? d,
    int? l,
    int? gf,
    int? ga,
  }) {
    return StandingsRow(
      teamId: teamId,
      teamName: teamName,
      mp: mp ?? this.mp,
      w: w ?? this.w,
      d: d ?? this.d,
      l: l ?? this.l,
      gf: gf ?? this.gf,
      ga: ga ?? this.ga,
    );
  }

  static StandingsRow empty({
    required String teamId,
    required String teamName,
  }) {
    return StandingsRow(
      teamId: teamId,
      teamName: teamName,
      mp: 0,
      w: 0,
      d: 0,
      l: 0,
      gf: 0,
      ga: 0,
    );
  }
}
