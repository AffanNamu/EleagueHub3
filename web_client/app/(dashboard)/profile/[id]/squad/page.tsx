'use client';

import { useState } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { SquadPitchView } from '@/components/profile/SquadPitchView';
import { useSquadGames, useSquad } from '@/hooks/useTeamProfile';
import { saveSquadWeb } from '@/lib/profile/teamProfileRepository';
import { SUPPORTED_FORMATIONS } from '@/lib/profile/squadLogic';
import { ArrowLeft, Edit2, Loader2, Gamepad2, Save, Wand2 } from 'lucide-react';
import { SquadData } from '@/lib/profile/teamProfileRepository';

export default function SquadEditorScreen() {
  const router = useRouter();
  const params = useParams();
  const targetUid = params.id as string;
  
  const isOwner = auth.currentUser?.uid === targetUid;

  const { games, loading: gamesLoading } = useSquadGames(targetUid);
  const [selectedGame, setSelectedGame] = useState(games[0] || 'local_football');
  const { squad, loading: squadLoading } = useSquad(targetUid, selectedGame);

  const [saving, setSaving] = useState(false);

  if (gamesLoading || squadLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>;

  if (!isOwner) {
    return (
      <div className="max-w-4xl mx-auto pb-20 px-4 sm:px-6">
        <div className="flex items-center gap-4 mb-6">
          <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl"><ArrowLeft className="w-5 h-5"/></button>
          <h1 className="text-2xl font-black text-white">Squad Preview</h1>
        </div>
        <div className="h-[600px] max-w-xl mx-auto"><SquadPitchView gameId={selectedGame} userId={targetUid}/></div>
      </div>
    );
  }

  const handleFormationChange = async (f: string) => {
    if (!squad) return;
    setSaving(true);
    const updated: SquadData = { ...squad, formation: f };
    await saveSquadWeb(targetUid, updated);
    setSaving(false);
  };

  return (
    <div className="max-w-4xl mx-auto pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white"/>
        </button>
        <div>
          <h1 className="text-2xl font-black text-[#38BDF8] flex items-center gap-2">
            <Edit2 className="w-5 h-5"/> Squad Editor
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Select your game, formation, and starting XI.</p>
        </div>
      </div>

      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl mb-6 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <label className="text-xs font-black uppercase tracking-widest text-gray-500 mb-2 block">Game Format</label>
          <select value={selectedGame} onChange={e => setSelectedGame(e.target.value)} className="bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-2 text-sm font-bold text-white outline-none focus:border-[#38BDF8]">
            {games.map(g => <option key={g} value={g}>{g.replace('_', ' ').toUpperCase()}</option>)}
          </select>
        </div>

        <div>
          <label className="text-xs font-black uppercase tracking-widest text-gray-500 mb-2 block">Formation Preset</label>
          <div className="flex gap-2 overflow-x-auto custom-scrollbar pb-2">
            {SUPPORTED_FORMATIONS.map(f => (
              <button 
                key={f} onClick={() => handleFormationChange(f)} disabled={saving}
                className={`px-4 py-2 rounded-xl text-xs font-black transition-colors border ${squad?.formation === f ? 'bg-[#38BDF8] text-[#0F172A] border-[#38BDF8]' : 'bg-[#070B14] text-gray-400 border-[#1E293B] hover:border-gray-500'}`}
              >
                {f}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="h-[600px] max-w-xl mx-auto rounded-3xl shadow-2xl relative">
        <SquadPitchView gameId={selectedGame} userId={targetUid}/>
      </div>
      
      <div className="mt-8 text-center bg-sky-500/10 border border-sky-500/20 text-sky-400 p-4 rounded-2xl text-sm font-bold">
        Web Interface: Drag and Drop player placement is currently read-only on desktop. <br/>
        Please use the Mobile App to add or swap players onto the pitch.
      </div>
    </div>
  );
}
