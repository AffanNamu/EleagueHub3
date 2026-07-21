'use client';

import { useEffect, useState } from 'react';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { getEntitlementFromClaims } from '@/lib/masterLeagues/entitlements';
import { countOwnedWorkspaces } from '@/lib/masterLeagues/masterLeaguesRepository';
import { MasterLeaguePlanId, MASTER_LEAGUE_PLANS } from '@/types/masterLeague';

export interface UseEntitlementsResult {
  activePlan: MasterLeaguePlanId; // 'basic' if no paid plan — every signed-in user gets it free
  paidPlanActive: boolean;
  ownedCount: number;
  loading: boolean;
  refresh: () => Promise<void>;
}

export function useEntitlements(): UseEntitlementsResult {
  const [activePlan, setActivePlan] = useState<MasterLeaguePlanId>('basic');
  const [paidPlanActive, setPaidPlanActive] = useState(false);
  const [ownedCount, setOwnedCount] = useState(0);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const uid = auth.currentUser?.uid;
    if (!uid) {
      setActivePlan('basic');
      setPaidPlanActive(false);
      setOwnedCount(0);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const [ent, count] = await Promise.all([getEntitlementFromClaims(), countOwnedWorkspaces(uid)]);
      setActivePlan(ent.active && ent.plan ? ent.plan : 'basic');
      setPaidPlanActive(ent.active);
      setOwnedCount(count);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, () => {
      load();
    });
    return () => unsub();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { activePlan, paidPlanActive, ownedCount, loading, refresh: load };
}

export function canCreateWorkspace(plan: MasterLeaguePlanId, ownedCount: number): boolean {
  const def = MASTER_LEAGUE_PLANS[plan];
  if (def.unlimitedMasterLeagues) return true;
  return ownedCount < def.maxMasterLeagues;
}
