'use client';

import { useState } from 'react';
import { useMarketplace } from '@/hooks/useMarketplace';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Store, Tag, Lightbulb } from 'lucide-react';
import Link from 'next/link';

// Mirrors marketplace_screen.dart's category chip row exactly.
const CATEGORIES = ['All', 'Gamepads', 'Jerseys', 'Boots', 'Accessories'];

export default function MarketplaceScreen() {
  const [category, setCategory] = useState('All');
  const { products, loading, error } = useMarketplace(category);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <div className="p-3 bg-brand-lime/10 rounded-xl">
          <Store className="w-6 h-6 text-brand-lime" />
        </div>
        <div>
          <h1 className="text-3xl font-bold text-white">Marketplace</h1>
          <p className="text-gray-400">Gaming & sports gear</p>
        </div>
      </div>

      {/* Category chips */}
      <div className="flex gap-2 overflow-x-auto pb-1">
        {CATEGORIES.map((c) => (
          <button
            key={c}
            onClick={() => setCategory(c)}
            className={`shrink-0 px-3.5 py-2 rounded-2xl text-xs font-black transition-colors border ${
              category === c
                ? 'bg-brand-lime/10 text-brand-lime border-brand-lime/40'
                : 'bg-white/[0.03] text-gray-400 border-white/10 hover:text-white'
            }`}
          >
            {c}
          </button>
        ))}
      </div>

      {error && (
        <div className="bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          Error loading marketplace: {error}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      ) : products.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <Tag className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Items Found</h3>
          <p className="text-gray-400 mt-2">
            {category === 'All' ? 'There are currently no items listed in the marketplace.' : `No products in ${category} yet.`}
          </p>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {products.map((product) => (
            <Link href={`/marketplace/${product.productId}`} key={product.productId}>
              <Glass className="overflow-hidden hover:scale-[1.02] transition-transform cursor-pointer group flex flex-col h-full">
                <div className="h-48 bg-brand-surfaceDark relative">
                  {product.imageUrl ? (
                    <img src={product.imageUrl} alt={product.name} className="w-full h-full object-cover" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center bg-gradient-to-br from-brand-navy to-brand-surface">
                      <Store className="w-10 h-10 text-brand-lime/30" />
                    </div>
                  )}
                </div>

                <div className="p-4 flex flex-col flex-1">
                  <h3 className="text-lg font-bold text-white truncate mb-1">{product.name || 'Untitled'}</h3>
                  <p className="text-xs text-gray-400 mb-3 flex-1 line-clamp-2">{product.description}</p>

                  <div className="flex items-end justify-between mt-auto pt-4 border-t border-white/5">
                    <div>
                      <p className="text-[10px] text-gray-500 uppercase tracking-wider mb-0.5">Price</p>
                      <p className="text-lg font-black text-brand-lime tabular-nums">{product.price || '—'}</p>
                    </div>
                    <p className="text-xs text-gray-400">By {product.sellerName || 'Seller'}</p>
                  </div>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}

      {/* Mirrors marketplace_screen.dart's _AffiliateDisclosureCard. */}
      <Glass className="p-4 flex items-start gap-3">
        <div className="w-9 h-9 rounded-full bg-brand-lime/10 flex items-center justify-center shrink-0">
          <Lightbulb className="w-4.5 h-4.5 text-brand-lime" />
        </div>
        <div>
          <p className="text-sm font-black text-white">Affiliate Disclosure</p>
          <p className="text-xs text-gray-400 mt-1 leading-relaxed">
            This marketplace contains affiliate products. We may earn commission from purchases.
          </p>
        </div>
      </Glass>
    </div>
  );
}
