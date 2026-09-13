import { useState, useEffect } from 'react';
import { watchRecentAnnouncementsWeb, PlatformAnnouncement } from '@/lib/social/platformAnnouncementsRepository';

export type { PlatformAnnouncement };

// Backed by platformAnnouncementsRepository.ts, which mirrors the Dart
// PlatformAnnouncementsRepository schema exactly (severity/active fields,
// not the ad-hoc type/no-filter shape this hook used before).
export function usePlatformAnnouncements(maxItems = 3) {
  const [announcements, setAnnouncements] = useState<PlatformAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = watchRecentAnnouncementsWeb((items) => {
      setAnnouncements(items);
      setLoading(false);
    }, maxItems);

    return () => unsubscribe();
  }, [maxItems]);

  return { announcements, loading };
}
