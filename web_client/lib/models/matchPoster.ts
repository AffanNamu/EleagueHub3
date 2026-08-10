// lib/models/matchPoster.ts
//
// Pure data shapes for the Match Poster feature. Mirrors
// lib/features/leagues/models/match_poster_data.dart on the Flutter side
// so the two platforms agree on what a "poster" is made of, even though
// the rendering pipelines are completely different (Satori/next-og here
// vs RepaintBoundary there).

export type MatchPosterFormat = 'portrait' | 'square' | 'story';

export const MATCH_POSTER_SIZES: Record<MatchPosterFormat, { width: number; height: number }> = {
  portrait: { width: 1080, height: 1350 },
  square: { width: 1080, height: 1080 },
  story: { width: 1080, height: 1920 },
};

export const MATCH_POSTER_FORMAT_LABELS: Record<MatchPosterFormat, string> = {
  portrait: 'Portrait',
  square: 'Square',
  story: 'Story',
};

export function isMatchPosterFormat(v: string | null | undefined): v is MatchPosterFormat {
  return v === 'portrait' || v === 'square' || v === 'story';
}

export interface MatchPosterTeamData {
  name: string;
  imageUrl: string;
}

export interface MatchPosterData {
  competitionName: string;
  competitionLogoUrl: string;
  season?: string;
  footballCategory?: string;
  home: MatchPosterTeamData;
  away: MatchPosterTeamData;
  /** e.g. "Round 3" or "Group A • Round 3" — built from real match fields only. */
  roundLabel?: string;
  /** Organizer-entered, optional. Undefined means "not shown" — this app
   *  does not store a scheduled date/time on FixtureMatch, so nothing is
   *  ever fabricated here. */
  dateTimeLabel?: string;
  /** Organizer-entered, optional. Same reasoning as dateTimeLabel. */
  venueLabel?: string;
}
