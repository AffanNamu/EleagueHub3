'use client';

import { useRouter } from 'next/navigation';
import { ArrowLeft, Edit2 } from 'lucide-react';
import { auth } from '@/lib/firebase';
import { SquadPitchView } from '@/components/profile/SquadPitchView';

export default function SquadEditorScreen() {
  const router = useRouter();
  const userId = auth.currentUser?.uid;

  if (!userId) return null;

  return (
    <div className="max-w-4xl mx-auto pb-20">
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

      <div className="h-[600px] max-w-xl mx-auto">
        {/* We pass the currently active user to the squad pitch */}
        <SquadPitchView gameId="localFootball" userId="{userId}"/>
      </div>
      
      <div className="mt-8 text-center text-sm font-bold text-gray-500">
        Drag and drop coming soon to the web interface.
      </div>
    </div>
  );
}
