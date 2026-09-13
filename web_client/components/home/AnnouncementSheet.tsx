'use client';

import { useEffect, useState } from 'react';
import { X, ShieldAlert, AlertTriangle, Megaphone } from 'lucide-react';
import { doc, getDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { markAnnouncementSeenWeb, type HomeContentItem } from '@/lib/social/homeContentRepository';

const SEVERITY_STYLES: Record<HomeContentItem['severity'], { icon: typeof Megaphone; color: string }> = {
  info: { icon: Megaphone, color: '#38BDF8' },
  warning: { icon: AlertTriangle, color: '#F59E0B' },
  critical: { icon: ShieldAlert, color: '#EF4444' },
};

/**
 * Modal bottom sheet for the single active announcement, shown once per
 * new announcement per user — replaces the old inline platform_announcements
 * banner. Tracks users/{uid}.lastSeenHomeAnnouncementAtMs so it doesn't
 * reappear on every visit, only when a newer announcement is posted.
 */
export function AnnouncementSheet({ announcement }: { announcement: HomeContentItem | null }) {
  const [visible, setVisible] = useState(false);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (!announcement) {
      // Handles the announcement being deactivated/removed while this is
      // mounted (visible already defaults to false on first mount).
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setVisible(false);
      return;
    }

    let cancelled = false;

    (async () => {
      const uid = auth.currentUser?.uid.trim();
      if (!uid) {
        if (!cancelled) {
          setVisible(true);
          setChecked(true);
        }
        return;
      }

      try {
        const snap = await getDoc(doc(db, 'users', uid));
        const lastSeen = snap.data()?.lastSeenHomeAnnouncementAtMs;
        const alreadySeen = typeof lastSeen === 'number' && lastSeen >= announcement.createdAtMs;
        if (!cancelled) {
          setVisible(!alreadySeen);
          setChecked(true);
        }
      } catch {
        if (!cancelled) {
          setVisible(true);
          setChecked(true);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [announcement]);

  if (!announcement || !checked || !visible) return null;

  const { icon: Icon, color } = SEVERITY_STYLES[announcement.severity];

  function dismiss() {
    if (announcement) void markAnnouncementSeenWeb(announcement.createdAtMs);
    setVisible(false);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="w-full max-w-md bg-[#0B1221] border border-[#1E293B] rounded-3xl shadow-2xl p-6 space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style={{ backgroundColor: `${color}1A`, border: `1px solid ${color}40` }}>
              <Icon className="w-5 h-5" style={{ color }} />
            </div>
            <h3 className="text-lg font-black text-white">{announcement.title}</h3>
          </div>
          <button onClick={dismiss} className="text-gray-500 hover:text-white shrink-0">
            <X className="w-5 h-5" />
          </button>
        </div>
        {announcement.subtitle && <p className="text-sm text-gray-400 leading-relaxed">{announcement.subtitle}</p>}
        <button
          onClick={dismiss}
          className="w-full py-3 bg-brand-lime text-[#070B14] font-black rounded-xl hover:brightness-110 transition-all"
        >
          Got it
        </button>
      </div>
    </div>
  );
}
