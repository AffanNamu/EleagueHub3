import { useState, useEffect } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { UserPlanSubscription, MasterLeaguePlan } from '@/types/masterLeague';

export function useEntitlements() {
  const [activePlan, setActivePlan] = useState<MasterLeaguePlan>('basic'); // Everyone gets basic for free
  const [subscription, setSubscription] = useState<UserPlanSubscription | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!auth.currentUser) {
      setLoading(false);
      return;
    }

    // Check user profile for active plan subscription (Matches _checkFirestoreProfile)
    const userRef = doc(db, 'users', auth.currentUser.uid);
    const unsubscribe = onSnapshot(userRef, (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        if (data.activePlanId) {
          const expires = data.planExpiresAtMs || 0;
          const now = Date.now();
          
          // Basic is lifetime free. Paid plans expire.
          if (data.activePlanId === 'basic' || expires > now) {
            setActivePlan(data.activePlanId as MasterLeaguePlan);
            setSubscription({
              plan: data.activePlanId,
              duration: data.activePlanDurationId,
              purchasedAtMs: data.planPurchasedAtMs,
              expiresAtMs: expires,
              receiptId: data.planReceiptId,
              provider: data.planProvider
            });
          } else {
            // Expired fallback to basic
            setActivePlan('basic'); 
          }
        }
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { activePlan, subscription, loading };
}
