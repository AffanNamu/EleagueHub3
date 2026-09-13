'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Loader2, ShieldAlert } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';
import { leagueFromRemoteMap, isOwnerForViewer } from '@/lib/models/league';

interface RoleGuardProps {
  leagueId: string;
  allowedRoles: ('admin' | 'owner' | 'moderator')[];
  children: React.ReactNode;
}

export const RoleGuard: React.FC<RoleGuardProps> = ({ leagueId, allowedRoles, children }) => {
  const [hasAccess, setHasAccess] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;

    const checkRole = async () => {
      const uid = auth.currentUser?.uid;
      if (!uid || !leagueId) return;

      try {
        // ── Single source of truth for ownership ──────────────────────────
        // This mirrors exactly how fetchFullLeagueDetails / the league
        // detail page determine ownership, so this guard never disagrees
        // with what the rest of the app already showed the user:
        //   1) league.organizerUid / organizerUserId matches the viewer, OR
        //   2) a doc in leagues/{id}/memberships/{uid} with role === 0
        // Previously this guard queried a non-existent "members" subcollection
        // expecting string roles, which always failed and denied everyone.
        const leagueRef = doc(db, 'leagues', leagueId);
        const membershipRef = doc(db, 'leagues', leagueId, 'memberships', uid);

        const [leagueSnap, membershipSnap] = await Promise.all([
          getDoc(leagueRef),
          getDoc(membershipRef),
        ]);

        if (!leagueSnap.exists()) {
          if (!cancelled) setHasAccess(false);
          return;
        }

        const league = leagueFromRemoteMap({ ...leagueSnap.data(), id: leagueSnap.id });

        const isOwnerByLeague = isOwnerForViewer(league, uid);
        const isOwnerByMembership = membershipSnap.exists() && membershipSnap.data()?.role === 0;
        const isOwner = isOwnerByLeague || isOwnerByMembership;

        // The app currently only models organizer vs. member. Treat any of
        // 'owner' / 'admin' / 'moderator' in allowedRoles as "requires
        // organizer access" until distinct admin/moderator roles exist
        // in Firestore.
        const requiresOwner =
          allowedRoles.includes('owner') ||
          allowedRoles.includes('admin') ||
          allowedRoles.includes('moderator');

        const access = requiresOwner ? isOwner : false;

        if (!cancelled) setHasAccess(access);
      } catch (error) {
        console.error('Error checking role', error);
        if (!cancelled) setHasAccess(false);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    checkRole();
    return () => {
      cancelled = true;
    };

  }, [leagueId, allowedRoles]);

  if (loading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  if (!hasAccess) {
    return (
      <div className="flex flex-col items-center justify-center py-20 p-4">
        <Glass className="max-w-md p-8 text-center flex flex-col items-center border-l-4 border-l-brand-red">
          <ShieldAlert className="w-12 h-12 text-brand-red mb-4" />
          <h2 className="text-xl font-bold text-white mb-2">Access Denied</h2>
          <p className="text-gray-400 mb-6">
            You do not have the required permissions ({allowedRoles.join(', ')}) to view this page.
          </p>
          <button 
            onClick={() => router.back()}
            className="px-6 py-2 bg-brand-surface hover:bg-white/10 text-white rounded-xl transition-colors border border-white/10"
          >
            Go Back
          </button>
        </Glass>
      </div>
    );
  }

  return <>{children}</>;
};
