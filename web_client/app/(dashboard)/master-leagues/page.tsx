'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useMyMasterLeagues } from '@/hooks/useMasterLeagues';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Network as Hub, Plus, ShieldCheck, Users } from 'lucide-react';
import Link from 'next/link';

export default function MasterLeaguesListScreen() {
  const router = useRouter();
  const [authUid, setAuthUid] = useState<string | null>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged(u => setAuthUid(u?.uid || null));
    return () => unsub();
  }, []);

  const { created, joined, loading } = useMyMasterLeagues(authUid);

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;

  return (
    <div className="max-w-5xl mx-auto space-y-8 pb-20 px-4 sm:px-6">
      <div className="flex items-center justify-between mt-4">
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white flex items-center gap-3">
            <Hub className="w-7 h-7 text-[#BEF264]"/> Master Leagues
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Organizer Workspaces & Brands</p>
        </div>
        <button onClick={() => router.push('/master-leagues/create')} className="px-5 py-2.5 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 shadow-lg flex items-center gap-2 transition-all active:scale-95">
          <Plus className="w-4 h-4"/> Create
        </button>
      </div>

      <div className="space-y-6">
        <h2 className="text-lg font-black text-white flex items-center gap-2 border-b border-[#1E293B] pb-2">
          <ShieldCheck className="w-5 h-5 text-[#38BDF8]"/> Created by You
        </h2>
        {created.length === 0 ? (
          <div className="p-8 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
            <p className="text-gray-500 font-bold">You haven't created any workspaces yet.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {created.map(ml => (
              <Link href={`/master-leagues/${ml.id}`} key={ml.id}>
                <Glass className="p-5 hover:bg-white/5 transition-colors border-[#1E293B] hover:border-white/10 group cursor-pointer h-full flex flex-col">
                  <div className="flex items-center gap-4 mb-4">
                    <div className="w-12 h-12 rounded-full bg-[#1E293B] overflow-hidden shrink-0 border border-white/5">
                      {ml.logoUrl ? <img src={ml.logoUrl} className="w-full h-full object-cover" alt="Logo" /> : <Hub className="w-6 h-6 m-auto mt-3 text-gray-500"/>}
                    </div>
                    <div>
                      <h3 className="font-black text-white text-lg group-hover:text-[#BEF264] transition-colors line-clamp-1">
                        {ml.name || 'Unnamed Organizer'}
                      </h3>
                      <p className="text-xs font-bold text-gray-400 uppercase tracking-widest">{ml.plan} Plan</p>
                    </div>
                  </div>
                  <div className="mt-auto pt-4 border-t border-[#1E293B] flex items-center justify-between text-xs font-bold text-gray-500">
                    <span>{ml.followersCount || 0} Followers</span>
                    <span>{ml.totalTournamentsCreated || 0} Competitions</span>
                  </div>
                </Glass>
              </Link>
            ))}
          </div>
        )}

        <h2 className="text-lg font-black text-white flex items-center gap-2 border-b border-[#1E293B] pb-2 mt-10">
          <Users className="w-5 h-5 text-amber-500"/> Joined Workspaces
        </h2>
        {joined.length === 0 ? (
          <div className="p-8 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
            <p className="text-gray-500 font-bold">You aren't a member or staff of any other workspaces.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {joined.map(ml => (
              <Link href={`/master-leagues/${ml.id}`} key={ml.id}>
                <Glass className="p-5 hover:bg-white/5 transition-colors border-[#1E293B] hover:border-white/10 group cursor-pointer h-full">
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-full bg-[#1E293B] overflow-hidden shrink-0 border border-white/5">
                      {ml.logoUrl ? <img src={ml.logoUrl} className="w-full h-full object-cover" alt="Logo" /> : <Hub className="w-6 h-6 m-auto mt-3 text-gray-500"/>}
                    </div>
                    <div>
                      <h3 className="font-black text-white text-lg group-hover:text-amber-500 transition-colors line-clamp-1">{ml.name}</h3>
                      <p className="text-xs font-bold text-gray-400 uppercase tracking-widest">Joined as Staff/Member</p>
                    </div>
                  </div>
                </Glass>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
