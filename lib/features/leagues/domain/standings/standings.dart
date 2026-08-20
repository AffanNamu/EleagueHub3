///leagues/domain/standings/standings.dart
/// Represents a single row in a league or group table.
///
/// This domain model calculates competitive statistics like:
/// - Base points (from match results)
/// - Goal difference
/// - Goals for
///
/// It also supports **admin point adjustments**:
/// - [adminAdjustment] is a net points delta applied by admins (can be negative)
/// - [finalPoints] is what the table should sort/display by in production
///
/// NOTE:
/// - We keep legacy fields (w/d/l etc.) because other parts of the app use them.
/// - For compatibility, [pts] returns [finalPoints] so existing UI that reads
///   `row.pts` will automatically reflect admin adjustments.
class StandingsRow {
  final String teamId;
  final String teamName;

  final int mp; // Matches Played
  final int w; // Wins
  final int d; // Draws
  final int l; // Losses
  final int gf; // Goals For
  final int ga; // Goals Against

  /// Net admin adjustment for this team (e.g. +3, -2).
  ///
  /// This is applied on top of [basePoints] to form [finalPoints].
  final int adminAdjustment;

  const StandingsRow({
    required this.teamId,
    required this.teamName,
    required this.mp,
    required this.w,
    required this.d,
    required this.l,
    required this.gf,
    required this.ga,
    this.adminAdjustment = 0,
  });

  /// Automatically calculates Goal Difference.
  int get gd => gf - ga;

  /// Base points from match results only (3 for win, 1 for draw).
  int get basePoints => w * 3 + d;

  /// Final points used for standings ordering and display.
  int get finalPoints => basePoints + adminAdjustment;

  /// Backwards compatible alias for points.
  ///
  /// IMPORTANT:
  /// - Historically this returned only base points.
  /// - In production with admin adjustments, callers should treat this as the
  ///   final table points (base + adminAdjustment).
  int get pts => finalPoints;

  StandingsRow copyWith({
    int? mp,
    int? w,
    int? d,
    int? l,
    int? gf,
    int? ga,
    int? adminAdjustment,
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
      adminAdjustment: adminAdjustment ?? this.adminAdjustment,
    );
  }

  static StandingsRow empty({
    required String teamId,
    required String teamName,
    int adminAdjustment = 0,
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
      adminAdjustment: adminAdjustment,
    );
  }
}
