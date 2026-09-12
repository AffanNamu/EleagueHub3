'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { resolveUsernameToUserId } from '@/lib/services/userProfileRepository';
import { recordLinkClick } from '@/lib/services/linkAnalyticsService';
import { ProfileDetailView } from '@/components/profile/ProfileDetailView';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Loader2, UserX } from 'lucide-react';

/**
 * The pretty `/u/{username}` share link — mirrors mobile's
 * UsernameProfileGateScreen: resolve username -> uid via the public
 * `usernames/{lower}` collection, record a "click" analytics event, set
 * the page title, then render the SAME profile UI as /profile/[id]
 * (via ProfileDetailView) WITHOUT redirecting/replacing the URL — a
 * visitor's address bar and any resharing they do keeps the pretty
 * username link, not an internal uid.
 */
export default function UsernameProfileGateScreen() {
  const params = useParams();
  const username = ((params.username as string) || '').trim();

  const [resolvedUid, setResolvedUid] = useState<string | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function resolve() {
      setLoading(true);
      setNotFound(false);
      setResolvedUid(null);

      const uid = await resolveUsernameToUserId(username).catch(() => null);
      if (cancelled) return;

      if (!uid) {
        setNotFound(true);
        setLoading(false);
        return;
      }

      recordLinkClick('userProfile', username.toLowerCase());

      try {
        const snap = await getDoc(doc(db, 'users', uid));
        const data = snap.data();
        const displayName = data?.teamName || data?.displayName || 'eSports Player';
        document.title = `${displayName} | eSportlyic`;
      } catch {
        document.title = 'eSportlyic';
      }

      setResolvedUid(uid);
      setLoading(false);
    }

    resolve();

    return () => {
      cancelled = true;
      document.title = 'eSportlyic';
    };
  }, [username]);

  if (loading) {
    return <div className="flex justify-center items-center h-[50vh]"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;
  }

  if (notFound || !resolvedUid) {
    return (
      <div className="flex flex-col items-center justify-center h-[50vh] text-gray-400 text-center px-4">
        <UserX className="w-12 h-12 mb-4 opacity-50"/>
        <p className="font-bold text-white">This profile is unavailable.</p>
        <p className="text-sm mt-1">The username may be misspelled, or this account no longer exists.</p>
      </div>
    );
  }

  return <ProfileDetailView routeUid={resolvedUid} />;
}
