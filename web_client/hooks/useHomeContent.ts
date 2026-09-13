import { useState, useEffect } from 'react';
import { watchHomeContentWeb, HomeContentItem } from '@/lib/social/homeContentRepository';

export function useHomeContent() {
  const [items, setItems] = useState<HomeContentItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = watchHomeContentWeb((next) => {
      setItems(next);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  return {
    loading,
    hero: items.filter((i) => i.type === 'hero'),
    promoCards: items.filter((i) => i.type === 'promo_card'),
    // Only the single highest-priority (lowest order) active announcement is shown as a bottom sheet.
    announcement: items.filter((i) => i.type === 'announcement')[0] ?? null,
  };
}
