import { useState, useEffect } from 'react';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { League } from '@/types/league';

type AccessStatus = 'loading' | 'allowed' | 'denied';

export function useLeagueAccess(league: League | null) {
  const [status, setStatus] = useState<AccessStatus>('loading');
  const [error, setError] = useState('');

  useEffect(() => {
    const checkAccess = async () => {
      if (!league) return;
      
      // 1. Unauthenticated users can only view Public Classic leagues
      if (!auth.currentUser) {
        if (league.format === 'classic' && league.privacy === 'public') {
          setStatus('allowed');
        } else {
          setStatus('denied');
        }
        return;
      }

      const uid = auth.currentUser.uid;

      // 2. Organizer always has access
      if (league.organizerId === uid) {
        setStatus('allowed');
        return;
      }

      try {
        // 3. Check for explicit membership (Participant, Paid, or Coupon)
        const membershipRef = doc(db, 'leagues', league.id, 'memberships', uid);
        const memSnap = await getDoc(membershipRef);

        if (memSnap.exists()) {
          setStatus('allowed');
          return;
        }

        // 4. Fallback: Classic Public leagues are free to enter (Read-Only)
        // If they enter, we silently sync their membership like Dart's ensureDeterministicMembershipBestEffort
        if (league.format === 'classic' && league.privacy === 'public') {
          await setDoc(membershipRef, {
            userId: uid,
            role: 'viewer',
            joinedAt: serverTimestamp()
          }, { merge: true });
          
          setStatus('allowed');
          return;
        }

        // 5. If none of the above, access is denied (Paywall / Coupon screen required)
        setStatus('denied');
      } catch (err: any) {
        console.error("Access Check Error:", err);
        setError("Failed to verify access.");
        setStatus('denied');
      }
    };

    checkAccess();
  }, [league, auth.currentUser]);

  return { status, error };
}
