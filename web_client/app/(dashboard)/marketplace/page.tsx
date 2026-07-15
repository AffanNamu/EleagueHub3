'use client';

import { useMarketplace } from '@/hooks/useMarketplace';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Search, Store, Tag } from 'lucide-react';
import Link from 'next/link';

export default function MarketplaceScreen() {
  const { products, loading, error } = useMarketplace();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-brand-lime/10 rounded-xl">
            <Store className="w-6 h-6 text-brand-lime" />
          </div>
          <div>
            <h1 className="text-3xl font-bold text-white">Marketplace</h1>
            <p className="text-gray-400">Browse gaming gear & accessories</p>
          </div>
        </div>
        
        <div className="relative w-full md:w-72">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input 
            type="text" 
            placeholder="Search products..." 
            className="w-full pl-10 pr-4 py-2 bg-brand-surface border border-white/10 rounded-xl text-white focus:outline-none focus:border-brand-lime transition-colors"
          />
        </div>
      </div>

      {/* Error State */}
      {error && (
        <div className="bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          Error loading marketplace: {error}
        </div>
      )}

      {/* Products Grid */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      ) : products.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <Tag className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Items Found</h3>
          <p className="text-gray-400 mt-2">There are currently no items listed in the marketplace.</p>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {products.map((product) => (
            <Link href={`/marketplace/${product.id}`} key={product.id}>
              <Glass className="overflow-hidden hover:scale-[1.02] transition-transform cursor-pointer group flex flex-col h-full">
                
                {/* Product Image */}
                <div className="h-48 bg-brand-surfaceDark relative">
                  {product.imageUrls && product.imageUrls.length > 0 ? (
                    <img 
                      src={product.imageUrls[0]} 
                      alt={product.title} 
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center bg-gradient-to-br from-brand-navy to-brand-surface">
                      <Store className="w-10 h-10 text-brand-lime/30" />
                    </div>
                  )}
                  
                  {/* Condition Badge */}
                  <div className="absolute top-2 right-2 px-2 py-1 bg-black/60 backdrop-blur-md rounded-lg text-xs font-semibold text-white border border-white/10 uppercase tracking-wider">
                    {product.condition}
                  </div>
                </div>
                
                {/* Product Details */}
                <div className="p-4 flex flex-col flex-1">
                  <h3 className="text-lg font-bold text-white truncate mb-1">{product.title}</h3>
                  <p className="text-xs text-gray-400 mb-3 flex-1 line-clamp-2">{product.description}</p>
                  
                  <div className="flex items-end justify-between mt-auto pt-4 border-t border-white/5">
                    <div>
                      <p className="text-[10px] text-gray-500 uppercase tracking-wider mb-0.5">Price</p>
                      <p className="text-lg font-black text-brand-lime tabular-nums">
                        {product.currency} {product.price.toLocaleString()}
                      </p>
                    </div>
                    <p className="text-xs text-gray-400">By {product.sellerName}</p>
                  </div>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
