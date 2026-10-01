'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { ArrowLeft, Check, Plus, Shield } from 'lucide-react';
import {
  getFixturesForTeam,
  getSquad,
  currentFootballSeasonGuess,
} from '@/lib/footballHub/footballHubRepository';
import { followTeam, isFollowingTeam, unfollowTeam } from '@/lib/footballHub/footballFollowsRepository';
import { FootballFixture, FootballSquadPlayer, isFinishedFixture } from '@/lib/footballHub/types';

export default function TeamPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const teamId = parseInt(params.id, 10);

  const [teamName, setTeamName] = useState<string>('');
  const [teamLogo, setTeamLogo] = useState<string>('');
  const [next, setNext] = useState<FootballFixture[] | null>(null);
  const [last, setLast] = useState<FootballFixture[] | null>(null);
  const [squad, setSquad] = useState<FootballSquadPlayer[] | null>(null);
  const [following, setFollowing] = useState<boolean | null>(null);

  useEffect(() => {
    getFixturesForTeam(teamId, { next: 1 }).then((f) => {
      setNext(f);
      if (f[0]) {
        const name = f[0].homeTeamId === teamId ? f[0].homeTeamName : f[0].awayTeamName;
        const logo = f[0].homeTeamId === teamId ? f[0].homeTeamLogoUrl : f[0].awayTeamLogoUrl;
        setTeamName((prev) => prev || name);
        setTeamLogo((prev) => prev || logo);
      }
    });
    getFixturesForTeam(teamId, { last: 5 }).then(setLast);
    getSquad(teamId).then(setSquad);
    isFollowingTeam(teamId).then(setFollowing);
  }, [teamId]);

  async function toggleFollow() {
    const prev = following ?? false;
    setFollowing(!prev);
    try {
      if (prev) await unfollowTeam(teamId);
      else await followTeam(teamId, teamName || `Team ${teamId}`, teamLogo || undefined);
    } catch {
      setFollowing(prev);
    }
  }

  return (
    <div className="min-h-screen bg-[#070B14] pb-20 md:pb-8">
      <div className="max-w-7xl mx-auto">
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 text-sm font-bold">
          <ArrowLeft className="w-4 h-4" /> Back
        </button>

        <div className="flex items-center gap-4 mb-6">
          {teamLogo ? (
            <img src={teamLogo} alt="" className="w-12 h-12 rounded-xl" />
          ) : (
            <div className="w-12 h-12 rounded-xl bg-[#1E293B] flex items-center justify-center">
              <Shield className="w-6 h-6 text-gray-400" />
            </div>
          )}
          <h1 className="text-xl font-black text-white flex-1">{teamName || `Team ${teamId}`}</h1>
          <button
            onClick={toggleFollow}
            disabled={following === null}
            className={`px-4 h-10 rounded-xl text-sm font-bold flex items-center gap-2 transition-colors disabled:opacity-60 ${
              following ? 'bg-[#BEF264]/10 text-[#BEF264] border border-[#BEF264]/30' : 'bg-[#1E293B]/50 text-white border border-[#1E293B]'
            }`}
          >
            {following ? <Check className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
            {following ? 'Following' : 'Follow'}
          </button>
        </div>

        <Section title="Next match">
          {next === null && <p className="text-sm text-gray-400">Loading...</p>}
          {next?.length === 0 && <p className="text-sm text-gray-400">No upcoming match scheduled.</p>}
          {next?.[0] && (
            <button
              onClick={() => router.push(`/football/match/${next[0].id}`)}
              className="w-full flex items-center justify-between bg-[#0B1221] border border-[#1E293B] rounded-xl px-4 py-3 text-left hover:border-[#BEF264]/30 transition-colors"
            >
              <span className="text-sm font-bold text-white">
                {next[0].homeTeamName} vs {next[0].awayTeamName}
              </span>
              <span className="text-xs text-gray-400">
                {next[0].kickoff.toLocaleDateString('en-US', { weekday: 'short', day: 'numeric', month: 'short' })},{' '}
                {next[0].kickoff.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
              </span>
            </button>
          )}
        </Section>

        <Section title="Last 5">
          {last === null && <p className="text-sm text-gray-400">Loading...</p>}
          {last?.length === 0 && <p className="text-sm text-gray-400">No recent results.</p>}
          <div className="flex gap-2">
            {last?.map((f) => <ResultBadge key={f.id} fixture={f} teamId={teamId} />)}
          </div>
        </Section>

        <Section title="Squad">
          {squad === null && <p className="text-sm text-gray-400">Loading...</p>}
          {squad?.length === 0 && <p className="text-sm text-gray-400">Squad not available.</p>}
          <div className="space-y-2">
            {squad?.map((p) => (
              <button
                key={p.id}
                onClick={() => router.push(`/football/player/${p.id}?season=${currentFootballSeasonGuess()}&name=${encodeURIComponent(p.name)}`)}
                className="w-full flex items-center gap-3 bg-[#0B1221] border border-[#1E293B] rounded-xl px-4 py-2.5 text-left hover:border-[#BEF264]/30 transition-colors"
              >
                {p.photoUrl ? (
                  <img src={p.photoUrl} alt="" className="w-8 h-8 rounded-full object-cover" />
                ) : (
                  <div className="w-8 h-8 rounded-full bg-[#1E293B]" />
                )}
                <span className="w-6 text-sm font-bold text-gray-400">{p.number ?? '-'}</span>
                <span className="flex-1 text-sm font-bold text-white truncate">{p.name}</span>
                <span className="text-xs text-gray-400">{p.position}</span>
              </button>
            ))}
          </div>
        </Section>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6">
      <p className="text-xs font-bold text-gray-400 mb-2">{title}</p>
      {children}
    </div>
  );
}

function ResultBadge({ fixture, teamId }: { fixture: FootballFixture; teamId: number }) {
  if (!isFinishedFixture(fixture) || fixture.homeGoals === null || fixture.awayGoals === null) {
    return <div className="w-7 h-7 rounded-full bg-gray-500 flex items-center justify-center text-[11px] font-black text-white">-</div>;
  }
  const isHome = fixture.homeTeamId === teamId;
  const own = isHome ? fixture.homeGoals : fixture.awayGoals;
  const opp = isHome ? fixture.awayGoals : fixture.homeGoals;
  let color = 'bg-amber-500';
  let letter = 'D';
  if (own > opp) {
    color = 'bg-[#22C55E]';
    letter = 'W';
  } else if (own < opp) {
    color = 'bg-red-500';
    letter = 'L';
  }
  return <div className={`w-7 h-7 rounded-full ${color} flex items-center justify-center text-[11px] font-black text-white`}>{letter}</div>;
}
