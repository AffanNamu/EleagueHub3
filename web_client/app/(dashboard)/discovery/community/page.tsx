'use client';

import { useRouter } from 'next/navigation';
import { Glass } from '@/components/ui/Glass';
import { MessageSquare, MessagesSquare, Film, BookOpen, ArrowLeft } from 'lucide-react';

export default function CommunityScreen() {
  const router = useRouter();

  const routes = [
    { icon: MessageSquare, color: 'text-purple-500', bg: 'bg-purple-500/10', title: 'Global Chat', subtitle: 'Request access & chat with the community in realtime', path: '/global-chat' },
    { icon: MessagesSquare, color: 'text-green-500', bg: 'bg-green-500/10', title: 'Discussions', subtitle: 'Ask questions, share tips, and talk tactics', path: '/discovery/community/discussions' },
    { icon: Film, color: 'text-sky-400', bg: 'bg-sky-400/10', title: 'Highlights', subtitle: 'Community match highlights', path: '#', badge: 'Soon' },
    { icon: BookOpen, color: 'text-amber-500', bg: 'bg-amber-500/10', title: 'Guides', subtitle: 'Tips, strategy, and how-tos from the community', path: '#', badge: 'Soon' },
  ];

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 px-4 sm:px-6 mt-4">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
      </div>

      <Glass className="p-6 md:p-8 border-[#1E293B] bg-[#0B1221] rounded-3xl shadow-xl mb-8">
        <h1 className="text-2xl font-black text-white">eSportlyic Community</h1>
        <p className="text-gray-400 font-semibold mt-2">Chat live, start discussions, and explore the wider eSportlyic community.</p>
      </Glass>

      <div className="space-y-4">
        {routes.map(r => (
          <button key={r.title} onClick={() => r.path !== '#' && router.push(r.path)} className="w-full text-left group">
            <Glass className="p-4 border-[#1E293B] bg-[#0B1221] hover:bg-white/5 hover:border-white/10 transition-colors rounded-2xl flex items-center gap-4">
              <div className={`w-12 h-12 rounded-full flex items-center justify-center shrink-0 ${r.bg}`}>
                <r.icon className={`w-6 h-6 ${r.color}`} />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <h3 className="font-black text-white text-lg group-hover:text-white">{r.title}</h3>
                  {r.badge && <span className="px-2 py-0.5 bg-gray-500/10 text-gray-400 border border-gray-500/30 rounded-lg text-[10px] font-black uppercase">{r.badge}</span>}
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
