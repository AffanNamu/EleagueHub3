'use client';

import { useEffect, useState, useCallback } from 'react';
import { MasterLeague } from '@/types/masterLeague';
import { discoverAll, discoverVerified } from '@/lib/masterLeagues/masterLeaguesRepository';

export function useOrganizerDiscovery() {
  const [hubs, setHubs] = useState<MasterLeague[]>([]);
  const [verified, setVerified] = useState<MasterLeague[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [all, ver] = await Promise.all([discoverAll(24), discoverVerified(12)]);
      setHubs(all);
      setVerified(ver);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return { hubs, verified, loading, refresh: load };
}
