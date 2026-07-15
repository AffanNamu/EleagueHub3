import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, orderBy, limit } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MarketplaceProduct } from '@/types/marketplace';

export function useMarketplace() {
  const [products, setProducts] = useState<MarketplaceProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Fetch available products ordered by newest
    const q = query(
      collection(db, 'marketplace'),
      where('isAvailable', '==', true),
      orderBy('createdAt', 'desc'),
      limit(50)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const productsData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as MarketplaceProduct[];
      
      setProducts(productsData);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching marketplace:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { products, loading, error };
}
