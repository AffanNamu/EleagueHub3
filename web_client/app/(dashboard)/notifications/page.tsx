'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { watchRecentAnnouncementsWeb, markAllSeenWeb, PlatformAnnouncement } from '@/lib/social/platformAnnouncementsRepository';
import { Glass } from '@/components/ui/Glass';
import { formatDistanceToNow } from 'date-fns';
import { ArrowLeft, Loader2, AlertTriangle, AlertCircle, Megaphone } from 'lucide-react';

/**
 * Full "view all" announcements inbox — the web counterpart of
 * notifications_list_screen.dart. The 3-item preview on the dashboard
 * home page links here for the complete, scrollable history. Marks
 * everything seen (bumps the per-user read cursor) as soon as the page
 * opens, same as the Dart screen.
 */
export default function NotificationsPage() {
  const router = useRouter();
  const [items, setItems] = useState<PlatformAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void markAllSeenWeb();
    const unsubscribe = watchRecentAnnouncementsWeb((data) => {
      setItems(data);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  function severityColor(severity: string) {
    if (severity === 'critical') return { text: 'text-brand-red', bg: 'bg-brand-red', Icon: AlertCircle };
    if (severity === 'warning') return { text: 'text-brand-lime', bg: 'bg-brand-lime', Icon: AlertTriangle };
    return { text: 'text-[#A78BFA]', bg: 'bg-[#A78BFA]', Icon: Megaphone };
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => router.back()} className="p-2 rounded-xl bg-[#0B1221] border border-[#1E293B] text-gray-400 hover:text-white">
          <ArrowLeft className="w-4 h-4" />
        </button>
        <h1 className="text-lg font-black text-white">Notifications</h1>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <Loader2 className="w-8 h-8 animate-spin text-[#A78BFA]" />
        </div>
      ) : items.length === 0 ? (
        <div className="text-center py-16">
          <p className="text-sm text-gray-500 font-medium">All systems operational. Nothing to see here.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((ann) => {
            const { text, bg, Icon } = severityColor(ann.severity);
            return (
              <Glass key={ann.id} className="p-4 border border-[#1E293B] bg-[#0B1221] relative overflow-hidden">
                <div className={`absolute left-0 top-0 bottom-0 w-1 ${bg}`} />
                <div className="flex items-center gap-2 mb-1.5">
                  <Icon className={`w-3.5 h-3.5 ${text}`} />
                  <p className={`text-[10px] ${text} font-black tracking-widest uppercase`}>{ann.severity}</p>
                </div>
                <h4 className="text-sm font-bold text-white mb-1.5 leading-snug">{ann.title}</h4>
                <p className="text-xs text-gray-400 leading-relaxed whitespace-pre-wrap">{ann.message}</p>
                <p className="text-[10px] text-gray-600 font-bold mt-3 tracking-wider uppercase">
                  {formatDistanceToNow(ann.createdAtMs)} ago
                </p>
              </Glass>
            );
          })}
        </div>
      )}
    </div>
  );
}
