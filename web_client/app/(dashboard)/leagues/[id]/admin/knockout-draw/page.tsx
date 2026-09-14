//leagues/[id]/admin/knockout-draw/page.tsx
'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useKnockoutMatches } from '@/hooks/useKnockoutMatches';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, GitMerge, Zap, ShieldAlert } from 'lucide-react';
import { seedTopNKnockouts } from '@/lib/algorithms/tournamentController';

export default function KnockoutDrawScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  const { matches, loading: matchesLoading } = useKnockoutMatches(leagueId);
  const { league } = useLeagueDetail(leagueId);
  const isDirectKnockout = league?.format === 'directKnockout';

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [teamCount, setTeamCount] = useState(8);
  const [includeThirdPlace, setIncludeThirdPlace] = useState(true);

  const DIRECT_KNOCKOUT_SIZES = [4, 8, 16, 32, 64];

  // Direct Knockout's bracket size is its whole participant capacity, not
  // a top-N pick — derive it from the actual roster instead of the
  // manual dropdown state, which only applies to other formats.
  const effectiveTeamCount = isDirectKnockout ? teams.length : teamCount;

  const handleGenerateBracket = async () => {
    if (matches.length > 0) {
      // Direct Knockout brackets are generated once and never regenerated
      // (matches the mobile app's _generateDirectKnockoutBracket, which
      // refuses outright rather than offering a wipe-and-redraw).
      if (isDirectKnockout) {
        return setError('A bracket has already been generated for this competition.');
      }
      if (!confirm("A knockout bracket already exists. Generating a new one will wipe the current bracket. Proceed?")) return;
    }

    if (isDirectKnockout && !DIRECT_KNOCKOUT_SIZES.includes(teams.length)) {
      return setError(
        `Direct Knockout needs exactly 4, 8, 16, 32, or 64 teams — currently ${teams.length}.`,
      );
    }

    // Direct Knockout has no group/qualification stage, so there are no
    // pre-knockout standings to seed by — cross-pair every registered
    // team in whatever order they were added, matching the mobile app.
    // Every other format seeds by current standings (finalPoints), since
    // this tool doubles as a general "re-seed the knockout stage from
    // standings" admin utility for them.
    const sortedTeams = isDirectKnockout
      ? teams
      : [...teams].sort((a, b) => {
          if ((b.finalPoints ?? 0) !== (a.finalPoints ?? 0)) return (b.finalPoints ?? 0) - (a.finalPoints ?? 0);
          return (b.goalDifference ?? 0) - (a.goalDifference ?? 0); // Tie breaker
        }).slice(0, effectiveTeamCount);

    if (sortedTeams.length < effectiveTeamCount) {
      return setError(`Not enough teams to generate a top-${effectiveTeamCount} bracket.`);
    }

    setLoading(true);
    setError('');

    try {
      // 1. Delete old bracket if it exists
      const batch = writeBatch(db);
      matches.forEach(m => {
        batch.delete(doc(db, 'leagues', leagueId, 'knockout', m.id));
      });

      // 2. Generate new mathematical bracket (cross-paired: 1st vs last, etc.)
      const rankedTeamIds = sortedTeams.map((t) => t.id);
      const generatedMatches = seedTopNKnockouts({ leagueId, rankedTeamIds, includeThirdPlace });

      if (generatedMatches.length === 0) {
        setError(`Could not seed a top-${effectiveTeamCount} bracket.`);
        setLoading(false);
        return;
      }

      // 3. Commit new matches
      generatedMatches.forEach(match => {
        const matchRef = doc(db, 'leagues', leagueId, 'knockout', match.id);
        batch.set(matchRef, match);
      });

      await batch.commit();
      alert(`Successfully generated a ${effectiveTeamCount}-team bracket!`);
      router.push(`/leagues/${leagueId}/knockout`);
    } catch (err) {
      console.error(err);
      setError(err instanceof Error ? err.message : 'Failed to generate bracket.');
    } finally {
      setLoading(false);
    }
  };

  if (teamsLoading || matchesLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#8B5CF6]"/></div>;

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-[#8B5CF6] flex items-center gap-2">
            <GitMerge className="w-6 h-6" />
            Knockout Draw Engine
          </h1>
          <p className="text-gray-400 mt-1">Seed the final phase of your tournament.</p>
        </div>
      </div>

      <Glass className="p-6 md:p-8">
        {error && (
          <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl mb-6">
            <ShieldAlert className="w-5 h-5 flex-shrink-0" />
            <span className="text-sm">{error}</span>
          </div>
        )}

        <div className="space-y-6">
          <div className="bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 p-4 rounded-xl text-sm text-[#8B5CF6]">
            {isDirectKnockout
              ? 'Direct Knockout has no group stage — every registered team is cross-paired (1st vs last) into a single bracket, generated once.'
              : 'This engine will automatically select the top ranked teams from your standings, cross-pair them (1st vs Last), and generate an interconnected bracket tree.'}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-bold text-gray-300 mb-2">Bracket Size (Power of 2)</label>
              {isDirectKnockout ? (
                <div className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white">
                  {teams.length} Teams (all registered teams)
                </div>
              ) : (
                <select
                  value={teamCount}
                  onChange={(e) => setTeamCount(parseInt(e.target.value))}
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-[#8B5CF6]"
                >
                  <option value={2}>2 Teams (Final Only)</option>
                  <option value={4}>4 Teams (Starts at Semis)</option>
                  <option value={8}>8 Teams (Quarter Finals)</option>
                  <option value={16}>16 Teams (Round of 16)</option>
                  <option value={32}>32 Teams (Round of 32 / World Cup)</option>
                  <option value={64}>64 Teams (Round of 64)</option>
                </select>
              )}
            </div>

            <div className="flex items-center justify-between pt-6">
              <label className="text-sm font-bold text-gray-300">Generate 3rd Place Match</label>
              <input
                type="checkbox"
                checked={includeThirdPlace}
                onChange={(e) => setIncludeThirdPlace(e.target.checked)}
                className="w-5 h-5 accent-[#8B5CF6]"
              />
            </div>
          </div>

          <div className="pt-6 border-t border-white/5">
            <button
              onClick={handleGenerateBracket}
              disabled={
                loading ||
                (isDirectKnockout
                  ? !DIRECT_KNOCKOUT_SIZES.includes(teams.length) || matches.length > 0
                  : teams.length < teamCount)
              }
              className="w-full py-4 bg-[#8B5CF6] text-white font-black rounded-xl hover:bg-[#7C3AED] transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-[#8B5CF6]/20"
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Zap className="w-5 h-5" />}
              Seed & Generate Bracket
            </button>
          </div>
        </div>
      </Glass>
    </div>
  );
}
