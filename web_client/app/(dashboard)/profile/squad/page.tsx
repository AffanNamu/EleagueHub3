'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { SquadPitchView } from '@/components/profile/SquadPitchView';
import { useSquadGames, useSquad } from '@/hooks/useTeamProfile';
import { saveSquadWeb, SquadData } from '@/lib/profile/teamProfileRepository';
import { SUPPORTED_FORMATIONS, ALL_GAME_IDS, gameLabel } from '@/lib/profile/squadLogic';
import { ArrowLeft, Edit2, Loader2 } from 'lucide-react';

export default function SquadEditorScreen() {
  const router = useRouter();
  const userId = auth.currentUser?.uid;

  // NOTE: `local_football` (with underscore) is GameId.localFootball on
  // mobile — see lib/features/profile/models/game_id.dart. Previously
  // this screen hardcoded "localFootball" here, which pointed at a
  // completely different Firestore doc than the mobile app, silently
  // orphaning any squad built on web.
  const { games, loading: gamesLoading } = useSquadGames(userId || null);
  const [selectedGame, setSelectedGame] = useState<string | null>(null);
  const activeGame = selectedGame || games[0] || 'local_football';

  const { squad, loading: squadLoading } = useSquad(userId || null, activeGame);
  const [saving, setSaving] = useState(false);

  if (!userId) return null;

  if (gamesLoading || squadLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" />
      </div>
    );
  }

  const addableGames = ALL_GAME_IDS.filter((g) => !games.includes(g));
  const isNewGame = !games.includes(activeGame);

  const handleFormationChange = async (f: string) => {
    if (!squad) return;
    setSaving(true);
    try {
      await saveSquadWeb(userId, { ...squad, formation: f } as SquadData);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl font-black text-[#38BDF8] flex items-center gap-2">
            <Edit2 className="w-5 h-5" /> Squad Editor
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Select your game, formation, and starting XI.</p>
        </div>
      </div>

      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl mb-6 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <label className="text-xs font-black uppercase tracking-widest text-gray-500 mb-2 block">Game Format</label>
          <select
            value={activeGame}
            onChange={(e) => setSelectedGame(e.target.value)}
            className="bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2 text-sm font-bold text-white outline-none focus:border-[#38BDF8]"
          >
            {games.map((g) => (
              <option key={g} value={g}>{gameLabel(g)}</option>
            ))}
            {addableGames.map((g) => (
              <option key={g} value={g}>{gameLabel(g)} (new)</option>
            ))}
          </select>
          {isNewGame && (
            <p className="text-xs font-semibold text-sky-400 mt-2 max-w-[220px]">
              New game — pick a formation and add players below to save it to your profile.
            </p>
          )}
        </div>

        {squad && (
          <div>
            <label className="text-xs font-black uppercase tracking-widest text-gray-500 mb-2 block">Formation Preset</label>
            <div className="flex gap-2 overflow-x-auto custom-scrollbar pb-2">
              {SUPPORTED_FORMATIONS.map((f) => (
                <button
                  key={f}
                  onClick={() => handleFormationChange(f)}
                  disabled={saving}
                  className={`px-4 py-2 rounded-xl text-xs font-black transition-colors border ${
                    squad.formation === f ? 'bg-[#38BDF8] text-[#0F172A] border-[#38BDF8]' : 'bg-[#070B14] text-gray-400 border-[#1E293B] hover:border-gray-500'
                  }`}
                >
                  {f}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      <div className="max-w-xl mx-auto">
        <SquadPitchView key={activeGame} gameId={activeGame} userId={userId} isEditable />
      </div>
    </div>
  );
}
