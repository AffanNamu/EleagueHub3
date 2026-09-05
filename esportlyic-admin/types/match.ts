// types/match.ts
//
// Mirrors FixtureMatch and KnockoutMatch exactly, cross-checked against
// fixture_match.dart and knockout_match.dart directly.
//
// MatchStatus: enums.dart was not provided, so the full enum is unknown.
// Three values are DIRECTLY confirmed by name in the Dart source
// (MatchStatus.scheduled, .completed, .played — both .completed and
// .played are checked for "finished", suggesting some historical
// inconsistency between the two). The correction UI only ever WRITES one
// of these three confirmed values — never a guessed one — since an
// unrecognized status name falls back silently to 'scheduled' in
// FixtureMatch.fromJson, which would be a real, hard-to-notice bug if a
// wrong enum name were written from here.

export type MatchStatus = 'scheduled' | 'completed' | 'played' | string;

export interface FixtureMatch {
  id: string;
  leagueId: string;
  groupId: string | null;
  roundNumber: number;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number | null;
  awayScore: number | null;
  status: MatchStatus;
  sortIndex: number;
  updatedAtMs: number;
  version: number;
}

export interface KnockoutMatch {
  id: string;
  leagueId: string;
  roundName: string;
  homeTeamId: string | null;
  awayTeamId: string | null;
  homeScore: number | null;
  awayScore: number | null;
  status: MatchStatus;
  tiebreakWinnerTeamId: string | null;
  nextMatchId: string | null;
  loserGoesToMatchId: string | null;
  isSecondLeg: boolean;
}

export interface PointAdjustment {
  id: string;
  leagueId: string;
  teamId: string;
  type: 'ADDITION' | 'DEDUCTION';
  points: number;
  reason: string;
  adjustedBy: string;
  createdAtMs: number;
}

export interface LeagueTeamSummary {
  teamId: string;
  name: string;
}
