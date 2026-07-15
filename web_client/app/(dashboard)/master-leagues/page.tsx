'use client';

import { useMasterLeagues } from '@/hooks/useMasterLeagues';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Network, Verified, Users, PlusCircle } from 'lucide-react';
import Link from 'next/link';

export default function MasterLeaguesScreen() {
  const { workspaces, loading, error } = useMasterLeagues(false); // Fetching all public workspaces for discovery

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-brand-lime/10 rounded-xl border border-brand-lime/20">
            <Network className="w-6 h-6 text-brand-lime" />
          </div>
          <div>
            <h1 className="text-3xl font-bold text-white">Organizer Workspaces</h1>
            <p className="text-gray-400">Discover premium competition hubs</p>
          </div>
        </div>
        
        <button className="flex items-center justify-center gap-2 px-4 py-2 bg-brand-lime text-brand-navy font-bold rounded-xl hover:bg-brand-lime/90 transition-colors">
          <PlusCircle className="w-5 h-5" />
          Create Workspace
        </button>
      </div>

      {error && (
        <div className="bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          Error loading workspaces: {error}
        </div>
      )}

      {/* Grid */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      ) : workspaces.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <Network className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Workspaces Found</h3>
          <p className="text-gray-400 mt-2">Be the first to create a Master League!</p>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {workspaces.map((workspace) => (
            <Link href={`/master-leagues/${workspace.id}`} key={workspace.id}>
              <Glass className="overflow-hidden hover:scale-[1.02] transition-transform cursor-pointer group flex flex-col h-full relative">
                
                {/* Banner Image */}
                <div className="h-32 bg-brand-surfaceDark relative">
                  {workspace.organizerProfile?.bannerUrl ? (
                    <img 
                      src={workspace.organizerProfile.bannerUrl} 
                      alt="Banner" 
                      className="w-full h-full object-cover opacity-80"
                    />
                  ) : (
                    <div className="absolute inset-0 bg-gradient-to-r from-brand-navy to-[#0F172A]" />
                  )}
                  
                  {workspace.plan === 'elite' && (
                    <div className="absolute top-2 left-2 px-2 py-1 bg-purple-500/80 backdrop-blur-md rounded-lg text-[10px] font-black text-white uppercase tracking-wider">
                      ELITE PLAN
                    </div>
                  )}
                </div>
                
                {/* Logo & Details */}
                <div className="px-4 pb-4 flex flex-col flex-1 relative mt(-8)">
                  <div className="w-16 h-16 rounded-xl overflow-hidden border-4 border-brand-navy bg-brand-surfaceDark transform -translate-y-8 flex-shrink-0">
                     {workspace.organizerProfile?.logoUrl ? (
                       <img src={workspace.organizerProfile.logoUrl} className="w-full h-full object-cover" alt="Logo" />
                     ) : (
                       <div className="w-full h-full flex items-center justify-center bg-brand-surface">
                         <Network className="w-6 h-6 text-gray-400" />
                       </div>
                     )}
                  </div>

                  <div className="-mt-6 flex-1">
                    <h3 className="text-xl font-bold text-white flex items-center gap-2">
                      {workspace.name}
                      {workspace.verificationStatus === 'verified' && (
                        <Verified className="w-5 h-5 text-amber-400" />
                      )}
                    </h3>
                    <p className="text-sm text-gray-400 mt-1 line-clamp-2">
                      {workspace.organizerProfile?.bio || 'Official tournament organizer.'}
                    </p>
                  </div>

                  <div className="mt-4 pt-4 border-t border-white/5 flex items-center justify-between text-xs text-gray-400 font-medium">
                    <div className="flex items-center gap-1.5">
                      <Users className="w-4 h-4 text-brand-lime" />
                      {workspace.followersCount || 0} Followers
                    </div>
                    <div>
                      {workspace.analytics?.totalTournamentsCreated || 0} Tournaments
                    </div>
                  </div>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
