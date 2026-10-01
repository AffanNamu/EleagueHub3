'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { ArrowLeft, Check, Plus, User } from 'lucide-react';
import { getPlayer, currentFootballSeasonGuess } from '@/lib/footballHub/footballHubRepository';
import { followPlayer, isFollowingPlayer, unfollowPlayer } from '@/lib/footballHub/footballFollowsRepository';
import { FootballPlayerProfile } from '@/lib/footballHub/types';

export default function PlayerPage() {
  const params = useParams<{ id: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();
  const playerId = parseInt(params.id, 10);
  const season = parseInt(searchParams.get('season') || '', 10) || currentFootballSeasonGuess();
  const fallbackName = searchParams.get('name') || '';

  const [profile, setProfile] = useState<FootballPlayerProfile | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [following, setFollowing] = useState<boolean | null>(null);

  useEffect(() => {
    getPlayer(playerId, season)
      .then(setProfile)
      .catch((e) => setError(e.message || 'Football data temporarily unavailable. Please try again.'));
    isFollowingPlayer(playerId).then(setFollowing);
  }, [playerId, season]);

  async function toggleFollow() {
    const prev = following ?? false;
    setFollowing(!prev);
    try {
      if (prev) await unfollowPlayer(playerId);
      else await followPlayer(playerId, profile?.name || fallbackName || `Player ${playerId}`, profile?.photoUrl);
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

        {profile === undefined && <p className="text-sm text-gray-400">Loading...</p>}
        {error && <p className="text-sm text-red-400">{error}</p>}
        {profile === null && !error && (
          <p className="text-sm text-gray-400">No stats available for this player this season.</p>
        )}

        {profile && (
          <>
            <div className="flex items-center gap-4 mb-6">
              {profile.photoUrl ? (
                <img src={profile.photoUrl} alt="" className="w-16 h-16 rounded-full object-cover" />
              ) : (
                <div className="w-16 h-16 rounded-full bg-[#1E293B] flex items-center justify-center">
                  <User className="w-7 h-7 text-gray-400" />
                </div>
              )}
              <div className="flex-1">
                <h1 className="text-xl font-black text-white">{profile.name}</h1>
                <p className="text-sm text-gray-400">
                  {[profile.primaryPosition, profile.nationality, profile.age ? `${profile.age} yrs` : null].filter(Boolean).join(' · ')}
                </p>
                {profile.primaryTeamName && (
                  <div className="flex items-center gap-1.5 mt-1">
                    {profile.primaryTeamLogoUrl && <img src={profile.primaryTeamLogoUrl} alt="" className="w-4 h-4" />}
                    <span className="text-xs text-gray-400">{profile.primaryTeamName}</span>
                  </div>
                )}
              </div>
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

            <p className="text-xs font-bold text-gray-400 mb-2">{season} season</p>
            <div className="grid grid-cols-3 gap-3 bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 mb-6">
              <Stat label="Apps" value={profile.appearances} />
              <Stat label="Goals" value={profile.goals} />
              <Stat label="Assists" value={profile.assists} />
              <Stat label="Yellow" value={profile.yellowCards} />
              <Stat label="Red" value={profile.redCards} />
              <Stat label="Rating" value={profile.averageRating != null ? profile.averageRating.toFixed(2) : '-'} />
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="text-center">
      <p className="text-lg font-black text-white">{value}</p>
      <p className="text-[11px] font-bold text-gray-400">{label}</p>
    </div>
  );
}
