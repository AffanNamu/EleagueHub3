//app/dashboard/leagues/[id]/admin/fixtures/page.tsx
'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { collection, doc, setDoc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useMatches } from '@/hooks/useMatches';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, CalendarPlus, CalendarDays, Zap } from 'lucide-react';
import { FixtureMatch } from '@/types/match';
import { FixtureGenerator } from '@/lib/algorithms/fixtureGenerator';

export default function ManageFixturesScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  const { matches, loading: matchesLoading } = useMatches(leagueId);

  // Manual Form State
  const [homeTeamId, setHomeTeamId] = useState('');
  const [awayTeamId, setAwayTeamId] = useState('');
  const [roundNumber, setRoundNumber] = useState(1);
  const [matchDate, setMatchDate] = useState('');
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // 1. Manual Creation Logic
  const handleCreateMatch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!homeTeamId || !awayTeamId) return setError('Please select teams.');
    if (homeTeamId === awayTeamId) return setError('Teams must be different.');

    setLoading(true);
    try {
      const matchRef = doc(collection(db, 'leagues', leagueId, 'matches'));
      const newMatch: Partial<FixtureMatch> = {
        id: matchRef.id,
        leagueId: leagueId,
        homeTeamId,
        awayTeamId,
        status: 'scheduled',
        roundNumber: Number(roundNumber),
        sortIndex: 0,
        updatedAtMs: Date.now(),
        version: 1,
      };
      await setDoc(matchRef, newMatch);
      setHomeTeamId('');
      setAwayTeamId('');
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  // 2. Auto-Generation Logic (using the ported algorithms)
  const handleAutoGenerate = async () => {
    if (!league) return;
    if (matches.length > 0) {
      if (!confirm("This will generate additional matches. Are you sure? (Usually you only Auto-Generate once on an empty schedule).")) return;
    }

    setLoading(true);
    setError('');
    
    try {
      let newFixtures: Partial<FixtureMatch>[] = [];

      if (league.format === 'classic') {
        newFixtures = FixtureGenerator.generateClassicLeagueFixtures(league, teams);
      } else if (league.format === 'uclGroup' || league.format === 'worldCup') {
        newFixtures = FixtureGenerator.generateGroupStage(league, teams);
      } else {
        throw new Error("Auto-generation for Swiss formats currently requires the mobile app engine.");
      }

      // Batch write to Firestore (max 500 per batch)
      const batch = writeBatch(db);
      for (const match of newFixtures) {
        const matchRef = doc(db, 'leagues', leagueId, 'matches', match.id!);
        batch.set(matchRef, match);
      }
      
      await batch.commit();
      alert(`Successfully generated ${newFixtures.length} matches!`);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getTeamName = (id: string) => teams.find(t => t.id === id)?.name || 'Unknown Team';

  if (teamsLoading || matchesLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-brand-lime"/></div>;

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-10">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
            <ArrowLeft className="w-5 h-5 text-white" />
          </button>
          <div>
            <h1 className="text-2xl md:text-3xl font-bold text-brand-red flex items-center gap-2">
              <CalendarPlus className="w-6 h-6" />
              Schedule Fixtures
            </h1>
            <p className="text-gray-400 mt-1">Generate or manually create match pairings.</p>
          </div>
        </div>

        {/* Auto Generate Button */}
        <button 
          onClick={handleAutoGenerate}
          disabled={loading || teams.length < 2 || league?.format === 'uclSwiss'}
          className="flex items-center justify-center gap-2 px-6 py-3 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 disabled:opacity-50 transition-colors shadow-lg shadow-brand-lime/20"
        >
          {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Zap className="w-5 h-5" />}
          Auto-Generate Matches
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left Column: Manual Form */}
        <div className="lg:col-span-1 space-y-6">
          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-4">Manual Entry</h2>
            
            {error && <div className="text-xs text-brand-red mb-4">{error}</div>}
            
            <form onSubmit={handleCreateMatch} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-gray-300 mb-1">Round / Matchweek</label>
                <input type="number" min="1" value={roundNumber} onChange={(e) => setRoundNumber(parseInt(e.target.value) || 1)} className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime" required />
              </div>
              <div>
                <label className="block text-xs font-bold text-gray-300 mb-1">Home Team</label>
                <select value={homeTeamId} onChange={(e) => setHomeTeamId(e.target.value)} className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime" required>
                  <option value="" disabled>Select Home Team</option>
                  {teams.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-bold text-gray-300 mb-1">Away Team</label>
                <select value={awayTeamId} onChange={(e) => setAwayTeamId(e.target.value)} className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime" required>
                  <option value="" disabled>Select Away Team</option>
                  {teams.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </div>
              <button type="submit" disabled={loading} className="w-full py-3 bg-brand-surface border border-white/10 text-white font-bold rounded-lg hover:bg-white/10 flex items-center justify-center gap-2">
                <CalendarPlus className="w-4 h-4" /> Add Single Match
              </button>
            </form>
          </Glass>
        </div>

        {/* Right Column: List */}
        <div className="lg:col-span-2">
          <Glass className="p-6 h-full">
            <h2 className="text-lg font-bold text-white mb-4 flex justify-between items-center">
              <span>Fixture Database</span>
              <span className="text-sm font-normal text-brand-lime bg-brand-lime/10 px-2 py-1 rounded-md">{matches.length} Matches</span>
            </h2>

            {matches.length === 0 ? (
              <div className="text-center py-10 text-gray-500 flex flex-col items-center">
                <Zap className="w-12 h-12 mb-3 opacity-50 text-brand-lime" />
                <p>No matches yet. Click Auto-Generate to build the schedule based on your settings.</p>
              </div>
            ) : (
              <div className="space-y-3 max-h-[600px] overflow-y-auto pr-2">
                {matches.map((match) => (
                  <div key={match.id} className="flex flex-col sm:flex-row sm:items-center justify-between p-4 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/5 transition-colors gap-4">
                    <div className="flex flex-col gap-1">
                      <div className="flex items-center gap-2 text-[10px] font-black text-brand-red uppercase tracking-wider">
                        <span>Round {match.roundNumber}</span>
                        {match.groupId && <span className="bg-brand-red/10 px-1.5 py-0.5 rounded text-brand-red">{match.groupId}</span>}
                      </div>
                      <div className="flex items-center gap-2 text-sm font-bold text-white">
                        <span className="w-24 text-right truncate">{getTeamName(match.homeTeamId)}</span>
                        <span className="text-gray-500 px-2">VS</span>
                        <span className="w-24 text-left truncate">{getTeamName(match.awayTeamId)}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Glass>
        </div>
      </div>
    </div>
  );
}
