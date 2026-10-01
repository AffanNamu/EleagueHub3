'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Goal } from 'lucide-react';
import { auth } from '@/lib/firebase';
import { MatchesTab } from '@/components/footballHub/MatchesTab';
import { LeaguesTab } from '@/components/footballHub/LeaguesTab';
import { FollowingTab } from '@/components/footballHub/FollowingTab';

type Tab = 'matches' | 'leagues' | 'following';

export default function FootballHubPage() {
  const router = useRouter();
  const [uid, setUid] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('matches');

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (!user) {
        router.push('/login');
        return;
      }
      setUid(user.uid);
    });
    return () => unsubscribe();
  }, [router]);

  if (!uid) return null;

  return (
    <div className="min-h-screen bg-[#070B14] transition-colors duration-300 pb-20 md:pb-8">
      <div className="max-w-7xl mx-auto">
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 mb-6 flex items-center gap-4 shadow-lg shadow-black/20">
          <div className="w-14 h-14 rounded-2xl bg-[#16A34A]/10 flex items-center justify-center shrink-0">
            <Goal className="w-7 h-7 text-[#16A34A]" />
          </div>
          <div>
            <h1 className="text-2xl font-black text-white tracking-tight">Football Hub</h1>
            <p className="text-sm font-semibold text-gray-400 mt-1">Live scores &amp; football updates</p>
          </div>
        </div>

        <div className="flex gap-2 mb-6 border-b border-[#1E293B]">
          {(['matches', 'leagues', 'following'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-4 py-3 text-sm font-bold capitalize transition-colors border-b-2 -mb-px ${
                tab === t ? 'text-[#BEF264] border-[#BEF264]' : 'text-gray-400 border-transparent hover:text-white'
              }`}
            >
              {t}
            </button>
          ))}
        </div>

        {tab === 'matches' && <MatchesTab />}
        {tab === 'leagues' && <LeaguesTab />}
        {tab === 'following' && <FollowingTab />}
      </div>
    </div>
  );
}
