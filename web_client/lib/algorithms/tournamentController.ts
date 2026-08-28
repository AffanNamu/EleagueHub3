import { KnockoutMatch } from '@/types/match';
import { Team } from '@/types/league';
import { v4 as uuidv4 } from 'uuid';

export class TournamentController {
  
  // ── SEEDING LOGIC ──────────────────────────────────────────────────────────

  /**
   * Builds a standard power-of-two knockout bracket (e.g., 2, 4, 8, 16, 32 teams).
   */
  static seedKnockouts(leagueId: string, sortedTeams: Team[], includeThirdPlace: boolean = false): Partial<KnockoutMatch>[] {
    const numTeams = sortedTeams.length;
    if (numTeams < 2 || (numTeams & (numTeams - 1)) !== 0) {
      throw new Error("Number of teams for knockouts must be a power of 2 (2, 4, 8, 16, 32).");
    }

    const matches: Partial<KnockoutMatch>[] = [];
    const numRounds = Math.log2(numTeams);
    let currentRoundTeams = [...sortedTeams];
    let previousRoundMatches: Partial<KnockoutMatch>[] = [];

    for (let r = 1; r <= numRounds; r++) {
      const isFinal = r === 1;
      const isSemiFinal = r === 2;
      const roundMatchesCount = Math.pow(2, r - 1);
      
      let roundName = 'Round of ' + (roundMatchesCount * 2);
      if (isFinal) roundName = 'Final';
      else if (isSemiFinal) roundName = 'Semi Finals';
      else if (roundMatchesCount === 4) roundName = 'Quarter Finals';

      const currentRoundMatches: Partial<KnockoutMatch>[] = [];

      for (let i = 0; i < roundMatchesCount; i++) {
        const matchId = `${leagueId}-KO-${Date.now()}_${i + 1}_${r}`;
        
        let nextMatchId = undefined;
        if (!isFinal) {
          nextMatchId = previousRoundMatches[Math.floor(i / 2)]?.id;
        }

        const match: Partial<KnockoutMatch> = {
          id: matchId,
          leagueId,
          roundName,
          status: 'scheduled',
          isSecondLeg: false,
          nextMatchId,
        };

        currentRoundMatches.push(match);
        matches.push(match);
      }

      if (isSemiFinal && includeThirdPlace) {
        const thirdPlaceMatchId = `${leagueId}-3P-${Date.now()}_1`;
        matches.push({
          id: thirdPlaceMatchId,
          leagueId,
          roundName: '3rd Place',
          status: 'scheduled',
          isSecondLeg: false,
        });

        currentRoundMatches[0].loserGoesToMatchId = thirdPlaceMatchId;
        currentRoundMatches[1].loserGoesToMatchId = thirdPlaceMatchId;
      }

      previousRoundMatches = currentRoundMatches;
    }

    const firstRoundMatches = previousRoundMatches;
    for (let i = 0; i < firstRoundMatches.length; i++) {
      firstRoundMatches[i].homeTeamId = currentRoundTeams[i].id;
      firstRoundMatches[i].awayTeamId = currentRoundTeams[numTeams - 1 - i].id;
    }

    return matches;
  }

  // ── ADVANCEMENT LOGIC (Strict Parity with Flutter) ─────────────────────────

  /**
   * Automatic advancement after a KO match is confirmed.
   * Mirrors `processMatchResult` from `tournament_controller.dart`.
   */
  static processMatchResult(completedMatch: Partial<KnockoutMatch>, allMatches: Partial<KnockoutMatch>[]): Partial<KnockoutMatch>[] {
    const isFinished = completedMatch.status === 'completed' || completedMatch.status === 'played';
    if (!isFinished) return allMatches;

    // Aggregate logic for two-legged ties (Play-offs)
    if (completedMatch.roundName === 'Play-off') {
      if (!completedMatch.isSecondLeg) return allMatches;

      const hId = completedMatch.homeTeamId;
      const aId = completedMatch.awayTeamId;
      if (!hId || !aId) return allMatches;

      const nextId = completedMatch.nextMatchId;
      if (!nextId) return allMatches;

      const firstLeg = allMatches.find(m => 
        m.roundName === 'Play-off' && 
        !m.isSecondLeg && 
        m.nextMatchId === nextId && 
        ((m.homeTeamId === hId && m.awayTeamId === aId) || (m.homeTeamId === aId && m.awayTeamId === hId))
      );

      if (!firstLeg || (firstLeg.status !== 'completed' && firstLeg.status !== 'played')) return allMatches;

      let hTot = 0;
      let aTot = 0;

      // Add First Leg
      if (firstLeg.homeTeamId === hId) {
        hTot += firstLeg.homeScore || 0;
        aTot += firstLeg.awayScore || 0;
      } else {
        hTot += firstLeg.awayScore || 0;
        aTot += firstLeg.homeScore || 0;
      }

      // Add Second Leg (completedMatch)
      if (completedMatch.homeTeamId === hId) {
        hTot += completedMatch.homeScore || 0;
        aTot += completedMatch.awayScore || 0;
      } else {
        hTot += completedMatch.awayScore || 0;
        aTot += completedMatch.homeScore || 0;
      }

      let winnerId: string | undefined;
      if (hTot > aTot) winnerId = hId;
      else if (aTot > hTot) winnerId = aId;
      else winnerId = completedMatch.tiebreakWinnerTeamId;

      if (!winnerId) return allMatches;

      return allMatches.map(m => {
        if (m.id !== nextId) return m;
        if (!m.homeTeamId && m.awayTeamId) return { ...m, homeTeamId: winnerId };
        if (!m.awayTeamId && m.homeTeamId) return { ...m, awayTeamId: winnerId };
        if (!m.homeTeamId && !m.awayTeamId) return { ...m, homeTeamId: winnerId };
        if (m.awayTeamId !== winnerId) return { ...m, awayTeamId: winnerId };
        return m;
      });
    }

    // Standard single-match advancement (R32, R16, QF, SF, Final)
    let winnerId = completedMatch.winnerTeamId;
    if (!winnerId) {
      if ((completedMatch.homeScore || 0) > (completedMatch.awayScore || 0)) winnerId = completedMatch.homeTeamId;
      else if ((completedMatch.awayScore || 0) > (completedMatch.homeScore || 0)) winnerId = completedMatch.awayTeamId;
      else winnerId = completedMatch.tiebreakWinnerTeamId;
    }

    if (!winnerId) return allMatches;

    const loserId = winnerId === completedMatch.homeTeamId ? completedMatch.awayTeamId : completedMatch.homeTeamId;
    let updated = [...allMatches];

    // Replace the specific completed match in the array to ensure state is fresh
    const matchIndex = updated.findIndex(m => m.id === completedMatch.id);
    if (matchIndex !== -1) updated[matchIndex] = completedMatch;

    if (completedMatch.nextMatchId) {
      updated = this._advanceWinnerToNext(completedMatch, winnerId, updated);
    }

    if (loserId && completedMatch.roundName === 'Semi Finals' && completedMatch.loserGoesToMatchId) {
      updated = this._placeLoserToThirdPlace(completedMatch, loserId, updated);
    }

    return updated;
  }

  private static _seedIndexFromId(id: string): number {
    const idx = id.lastIndexOf('_');
    if (idx === -1 || idx + 1 >= id.length) return 0;
    return parseInt(id.substring(idx + 1)) || 0;
  }

  private static _slotForAdvancement(fromMatch: Partial<KnockoutMatch>, allMatches: Partial<KnockoutMatch>[]): 'home' | 'away' {
    const nextId = fromMatch.nextMatchId;
    if (!nextId) return 'home';

    const feeders = allMatches.filter(m => m.roundName === fromMatch.roundName && m.nextMatchId === nextId);
    if (feeders.length <= 1) return 'home';

    feeders.sort((a, b) => {
      const ai = this._seedIndexFromId(a.id || '');
      const bi = this._seedIndexFromId(b.id || '');
      if (ai !== bi) return ai - bi;
      return (a.id || '').localeCompare(b.id || '');
    });

    const pos = feeders.findIndex(m => m.id === fromMatch.id);
    const safePos = Math.max(0, pos);
    return safePos % 2 === 0 ? 'home' : 'away';
  }

  private static _advanceWinnerToNext(completedMatch: Partial<KnockoutMatch>, winnerId: string, allMatches: Partial<KnockoutMatch>[]): Partial<KnockoutMatch>[] {
    const nextId = completedMatch.nextMatchId;
    if (!nextId) return allMatches;

    const slot = this._slotForAdvancement(completedMatch, allMatches);

    return allMatches.map(m => {
      if (m.id !== nextId) return m;
      if (slot === 'home') return { ...m, homeTeamId: winnerId };
      return { ...m, awayTeamId: winnerId };
    });
  }

  private static _placeLoserToThirdPlace(completedSemi: Partial<KnockoutMatch>, loserId: string, allMatches: Partial<KnockoutMatch>[]): Partial<KnockoutMatch>[] {
    const thirdId = completedSemi.loserGoesToMatchId;
    if (!thirdId) return allMatches;

    const feeders = allMatches.filter(m => m.roundName === 'Semi Finals' && m.loserGoesToMatchId === thirdId);
    if (feeders.length === 0) return allMatches;

    feeders.sort((a, b) => {
      const ai = this._seedIndexFromId(a.id || '');
      const bi = this._seedIndexFromId(b.id || '');
      if (ai !== bi) return ai - bi;
      return (a.id || '').localeCompare(b.id || '');
    });

    const pos = feeders.findIndex(m => m.id === completedSemi.id);
    const safePos = Math.max(0, pos);
    const slot = safePos % 2 === 0 ? 'home' : 'away';

    return allMatches.map(m => {
      if (m.id !== thirdId) return m;
      if (slot === 'home') return { ...m, homeTeamId: loserId };
      return { ...m, awayTeamId: loserId };
    });
  }
}
