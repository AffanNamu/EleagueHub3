'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { collection, query, orderBy, limit, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MasterLeagueData } from '@/lib/masterLeagues/masterLeaguesRepository';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Globe, Search, ShieldCheck, Network as Hub } from 'lucide-react';
import Link from 'next/link';

export default function OrganizerDiscoveryScreen() {
  const router = useRouter();
  const [recent, setRecent] = useState<MasterLeagueData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      // Load recent active master leagues (Fallback discovery mechanism)
      const q = query(collection(db, 'master_leagues'), orderBy('updatedAtMs', 'desc'), limit(12));
      const snap = await getDocs(q);
      setRecent(snap.docs.map(d => ({ id: d.id, ...d.data() } as MasterLeagueData)));
      setLoading(false);
    }
    load();
  }, []);

  return (
    <div className="max-w-6xl mx-auto space-y-8 pb-20 px-4 sm:px-6">
      <div className="mt-6 mb-8 text-center">
        <div className="w-16 h-16 bg-[#38BDF8]/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-[#38BDF8]/20">
          <Globe className="w-8 h-8 text-[#38BDF8]" />
        </div>
        <h1 className="text-3xl font-black text-white">Organizer Discovery</h1>
        <p className="text-gray-400 mt-2 font-medium">Find official brands, verified workspaces, and active communities.</p>
      </div>

      <div className="relative max-w-xl mx-auto mb-12">
        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
        <input 
          placeholder="Search by @username..." 
          className="w-full bg-[#0B1221] border border-[#1E293B] rounded-2xl py-4 pl-12 pr-4 text-white font-bold outline-none focus:border-[#38BDF8] shadow-xl"
        />
      </div>

      <div>
        <h2 className="text-lg font-black text-white flex items-center gap-2 border-b border-[#1E293B] pb-2 mb-6">
          <ShieldCheck className="w-5 h-5 text-[#BEF264]" /> Recently Active
        </h2>
        
        {loading ? (
          <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 animate-spin text-[#BEF264]" /></div>
        ) : recent.length === 0 ? (
          <p className="text-center text-gray-500 font-bold py-10">No active organizers found.</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {recent.map(ml => (
              <Link key={ml.id} href={`/master-leagues/${ml.id}`}>
                <Glass className="p-5 hover:bg-white/5 transition-colors border-[#1E293B] hover:border-white/10 group cursor-pointer h-full flex flex-col bg-[#0B1221]">
                  <div className="flex items-center gap-4 mb-4">
                    <div className="w-14 h-14 rounded-full bg-[#1E293B] overflow-hidden shrink-0 border border-white/5">
                      {ml.logoUrl ? <img src={ml.logoUrl} className="w-full h-full object-cover" /> : <Hub className="w-6 h-6 m-auto mt-4 text-gray-500" />}
                    </div>
                    <div>
                      <h3 className="font-black text-white text-lg group-hover:text-[#38BDF8] transition-colors line-clamp-1">{ml.name || 'Organizer'}</h3>
                      {ml.verifiedBadge && <span className="text-[10px] font-black text-sky-400 uppercase tracking-widest">Verified</span>}
                    </div>
                  </div>
                  <div className="mt-auto pt-4 border-t border-[#1E293B] flex items-center justify-between text-[10px] font-black uppercase tracking-widest text-gray-500">
                    <span>{ml.followersCount || 0} Followers</span>
                    <span>{ml.totalTournamentsCreated || 0} Events</span>
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
