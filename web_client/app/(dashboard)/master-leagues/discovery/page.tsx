'use client';

import { useOrganizerDiscovery } from '@/hooks/useOrganizerDiscovery';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Network, Search, ShieldCheck } from 'lucide-react';
import Link from 'next/link';

export default function OrganizerDiscoveryScreen() {
  const { hubs, loading } = useOrganizerDiscovery();

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-10">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <Network className="w-6 h-6 text-[#38BDF8]" />
            Organizer Discovery
          </h1>
          <p className="text-gray-400 mt-1">Find top-rated eSports Hubs and communities.</p>
        </div>
        
        <div className="relative w-full md:w-64">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input 
            type="text" 
            placeholder="Search organizers..." 
            className="w-full pl-10 pr-4 py-2 bg-brand-surface border border-white/10 rounded-xl text-white focus:outline-none focus:border-[#38BDF8]"
          />
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>
      ) : hubs.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <Network className="w-16 h-16 text-gray-500 mb-4 opacity-50" />
          <h3 className="text-xl font-bold text-white">No Hubs Found</h3>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {hubs.map((ml) => (
            <Link href={`/master-leagues/${ml.id}`} key={ml.id}>
              <Glass className="p-6 hover:bg-white/5 transition-all group border-t-2 border-t-transparent hover:border-t-[#38BDF8]">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-16 h-16 bg-brand-surfaceDark rounded-xl overflow-hidden shrink-0">
                    {ml.organizerProfile?.logoUrl ? (
                      <img src={ml.organizerProfile.logoUrl} className="w-full h-full object-cover" alt="" />
                    ) : (
                      <Network className="w-8 h-8 m-auto text-gray-500 mt-4" />
                    )}
                  </div>
                  <div>
                    <h3 className="font-bold text-white text-lg group-hover:text-[#38BDF8] transition-colors line-clamp-1">{ml.name}</h3>
                    {ml.organizerProfile?.isVerified && (
                      <span className="flex items-center gap-1 text-[10px] text-brand-lime font-bold uppercase tracking-wider">
                        <ShieldCheck className="w-3 h-3" /> Verified
                      </span>
                    )}
                  </div>
                </div>
                <p className="text-sm text-gray-400 line-clamp-2 mb-4 h-10">{ml.description || 'No description provided.'}</p>
                <div className="flex items-center justify-between pt-4 border-t border-white/5">
                  <span className="text-xs font-bold text-gray-500 uppercase tracking-widest">{ml.followersCount || 0} Followers</span>
                  <span className="text-xs text-[#38BDF8] font-bold">View Network &rarr;</span>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
