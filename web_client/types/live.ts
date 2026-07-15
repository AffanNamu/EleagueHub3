export interface LiveSession {
  id: string;
  leagueId: string;
  matchId: string;
  hostId: string;
  hostName: string;
  title: string;
  livekitRoomName: string;
  isLive: boolean;
  viewersCount: number;
  homeTeamScore: number;
  awayTeamScore: number;
  homeTeamName: string;
  awayTeamName: string;
  createdAt: any; // Firestore Timestamp
}
