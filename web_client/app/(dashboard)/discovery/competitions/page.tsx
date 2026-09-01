'use client';

import { useRouter } from 'next/navigation';
import { usePublicCompetitions } from '@/hooks/useDiscovery';
import { Glass } from '@/components/ui/Glass';
import { LeagueCard } from '@/components/leagues/LeagueCard';
import { ArrowLeft, Loader2, Trophy } from 'lucide-react';

export default function CompetitionsDiscoveryScreen() {
  const router = useRouter();
  const { leagues, loading } = usePublicCompetitions();

  return (
    <div className="max-w-5xl mx-auto space-y-6 pb-20 px-4 sm:px-6 mt-4">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl md:text-2xl font-black text-white flex items-center gap-2">
          <Trophy className="w-6 h-6 text-sky-400" /> Public Competitions
        </h1>
      </div>

      {loading ? (
        <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-sky-400" /></div>
      ) : leagues.length === 0 ? (
        <div className="p-16 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
          <Trophy className="w-12 h-12 text-gray-600 mx-auto mb-4" />
          <p className="text-white font-bold text-lg">No public competitions yet.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {leagues.map(l => (
            <div key={l.id} className="h-[250px]">
              <LeagueCard league={l} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
