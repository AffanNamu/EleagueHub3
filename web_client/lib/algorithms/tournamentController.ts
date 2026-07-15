import { KnockoutMatch } from '@/types/match';
import { Team } from '@/types/league';
import { v4 as uuidv4 } from 'uuid';

export class TournamentController {
  /**
   * Builds a standard power-of-two knockout bracket (e.g., 2, 4, 8, 16, 32 teams).
   * Maps exactly to the Flutter _buildKnockoutTree logic.
   */
  static seedKnockouts(leagueId: string, sortedTeams: Team[], includeThirdPlace: boolean = false): Partial<KnockoutMatch>[] {
    const numTeams = sortedTeams.length;
    // Ensure power of 2
    if (numTeams < 2 || (numTeams & (numTeams - 1)) !== 0) {
      throw new Error("Number of teams for knockouts must be a power of 2 (2, 4, 8, 16, 32).");
    }

    const matches: Partial<KnockoutMatch>[] = [];
    const numRounds = Math.log2(numTeams);
    let currentRoundTeams = [...sortedTeams];
    
    // Arrays to keep track of generated match IDs to link nextMatchId
    let previousRoundMatches: Partial<KnockoutMatch>[] = [];

    // Build from Final down to the first round to easily link nextMatchId
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
        const matchId = uuidv4();
        
        let nextMatchId = undefined;
        let loserGoesToMatchId = undefined;

        if (!isFinal) {
          // Link to the parent match in the next round (integer division by 2)
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

      // If it's the Semi Final round and we want a 3rd place match, create it and link the losers
      if (isSemiFinal && includeThirdPlace) {
        const thirdPlaceMatchId = uuidv4();
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

    // Now, seed the very first round with actual Team IDs
    // Standard cross-seeding (1 vs 16, 2 vs 15, etc.)
    const firstRoundMatches = previousRoundMatches; // The last generated round is the first chronologically
    for (let i = 0; i < firstRoundMatches.length; i++) {
      // Logic for standard 1v8, 2v7 seeding could be mapped here depending on Swiss vs Group.
      // For basic initialization, we pair sequentially or cross-pair.
      firstRoundMatches[i].homeTeamId = currentRoundTeams[i].id;
      firstRoundMatches[i].awayTeamId = currentRoundTeams[numTeams - 1 - i].id;
    }

    return matches;
  }
}
