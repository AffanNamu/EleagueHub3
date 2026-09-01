'use client';

import { useRouter } from 'next/navigation';
import { Glass } from '@/components/ui/Glass';
import { Flame, Trophy, Network as Hub, Users, Globe } from 'lucide-react';

export default function DiscoveryHubScreen() {
  const router = useRouter();

  const routes = [
    { icon: Flame, color: 'text-green-500', bg: 'bg-green-500/10', title: 'Public Feed', subtitle: "See what's happening in the community", path: '/feed', badge: 'HOT' },
    { icon: Trophy, color: 'text-sky-400', bg: 'bg-sky-400/10', title: 'Competitions', subtitle: 'Find leagues, tournaments and upcoming matches', path: '/discovery/competitions' },
    { icon: Hub, color: 'text-purple-500', bg: 'bg-purple-500/10', title: 'Organizers', subtitle: 'Discover verified organizers and workspaces', path: '/master-leagues/discovery' },
    { icon: Users, color: 'text-teal-400', bg: 'bg-teal-400/10', title: 'Teams', subtitle: 'Find competitive teams and squads', path: '/search' },
    { icon: Globe, color: 'text-amber-500', bg: 'bg-amber-500/10', title: 'Community', subtitle: 'Explore global eSportlyic content and discussions', path: '/discovery/community' },
  ];

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 px-4 sm:px-6 mt-6">
      <div className="mb-8">
        <p className="text-[#BEF264] font-black text-xs tracking-widest uppercase mb-2">Discovery</p>
        <h1 className="text-3xl font-black text-white">Discover eSportlyic</h1>
        <p className="text-gray-400 font-semibold mt-2">Explore competitions, organizers, teams and the global eSportlyic community.</p>
      </div>

      <div className="space-y-4">
        {routes.map(r => (
          <button key={r.title} onClick={() => router.push(r.path)} className="w-full text-left group">
            <Glass className="p-4 border-[#1E293B] bg-[#0B1221] hover:bg-white/5 hover:border-white/10 transition-colors rounded-2xl flex items-center gap-4">
              <div className={`w-12 h-12 rounded-full flex items-center justify-center shrink-0 ${r.bg}`}>
                <r.icon className={`w-6 h-6 ${r.color}`} />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <h3 className="font-black text-white text-lg group-hover:text-white">{r.title}</h3>
                  {r.badge && <span className="px-2 py-0.5 bg-[#BEF264]/10 text-[#BEF264] border border-[#BEF264]/30 rounded-lg text-[10px] font-black uppercase">{r.badge}</span>}
                </div>
                <p className="text-xs font-bold text-gray-500">{r.subtitle}</p>
              </div>
            </Glass>
          </button>
        ))}
      </div>
    </div>
  );
}
