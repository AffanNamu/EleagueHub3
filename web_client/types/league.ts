export type LeagueFormat = 'classic' | 'uclGroup' | 'uclSwiss' | 'worldCup';
export type LeaguePrivacy = 'public' | 'private';
export type FootballCategory = 'localFootball' | 'proFootball' | 'esports'; // Matches your app's categories
export type WorldCupFormat = 'fifa2022' | 'fifa2026';

export interface LeagueSettings {
  doubleRoundRobin: boolean;
  groupSize: number;
  swissRounds: number;
  worldCupFormat?: WorldCupFormat;
  lastPulledAtMs?: number;
}

export interface League {
  memberIds?: string[];
  id: string;
  name: string;
  masterLeagueId?: string;
  description: string;
  coverImageUrl: string;
  sponsorImageUrl?: string;
  format: LeagueFormat;
  privacy: LeaguePrivacy;
  footballCategory: FootballCategory;
  homeAwayEnabled: boolean;
  maxTeams: number;
  settings: LeagueSettings;
  status: 'draft' | 'active' | 'completed';
  participantsCount: number;
  organizerId: string;
  createdAt: any; // Firestore Timestamp
  updatedAtMs?: number;
}

export interface Team {
  played?: number;
  won?: number;
  drawn?: number;
  lost?: number;
  goalsFor?: number;
  goalsAgainst?: number;
  goalDifference?: number;
  basePoints?: number;
  finalPoints?: number;
  adminAdjustment?: number;

  logoUrl?: string;
  teamImageUrl?: string;
  id: string;
  leagueId: string;
  name: string;
  ownerId: string;
  groupId?: string;




  updatedAtMs?: number;
}
