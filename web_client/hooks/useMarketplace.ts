import { useState, useEffect } from 'react';
import { collection, doc, onSnapshot, orderBy, query, where, limit as fsLimit } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MarketplaceProduct } from '@/types/marketplace';
import { marketplaceProductFromDoc, PRODUCTS_COLLECTION } from '@/lib/marketplace/marketplaceRepository';

/** Mirrors MarketplaceRepository.watchProducts(): filtering by category
 * queries on `category` alone (no orderBy) to avoid requiring a composite
 * index, sorting newest-first client-side instead; "All" (or no category)
 * orders by createdAt directly via the single-field index. */
export function useMarketplace(category?: string | null) {
  const [products, setProducts] = useState<MarketplaceProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cat = (category ?? '').trim();
  const hasCategory = cat.length > 0 && cat.toLowerCase() !== 'all';

  useEffect(() => {
    const timer = setTimeout(() => setLoading(true), 0);

    const col = collection(db, PRODUCTS_COLLECTION);
    const q = hasCategory
      ? query(col, where('category', '==', cat), fsLimit(120))
      : query(col, orderBy('createdAt', 'desc'), fsLimit(120));

    const unsubscribe = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => marketplaceProductFromDoc(d.id, d.data()));
        list.sort((a, b) => b.createdAt - a.createdAt);
        setProducts(list);
        setLoading(false);
        setError(null);
      },
      (err) => {
        console.error('[useMarketplace] failed:', err);
        setError(err.message);
        setLoading(false);
      },
    );

    return () => {
      clearTimeout(timer);
      unsubscribe();
    };
  }, [hasCategory, cat]);

  return { products, loading, error };
}

export function useMarketplaceProduct(productId: string) {
  const [product, setProduct] = useState<MarketplaceProduct | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!productId) return;
    const unsubscribe = onSnapshot(
      doc(db, PRODUCTS_COLLECTION, productId),
      (snap) => {
        setProduct(snap.exists() ? marketplaceProductFromDoc(snap.id, snap.data()) : null);
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsubscribe();
  }, [productId]);

  return { product, loading };
}
