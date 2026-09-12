'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMarketplaceProduct } from '@/hooks/useMarketplace';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, ShoppingCart, ExternalLink, ImageOff } from 'lucide-react';

function looksLikeHttpUrl(s: string): boolean {
  const u = s.trim().toLowerCase();
  return u.startsWith('https://') || u.startsWith('http://');
}

export default function ProductDetailsScreen() {
  const router = useRouter();
  const params = useParams();
  const productId = params.id as string;

  const { product, loading } = useMarketplaceProduct(productId);
  const [confirmOpen, setConfirmOpen] = useState(false);

  if (loading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }
  if (!product) {
    return <div className="text-center py-20 text-gray-500 font-bold">Product not found.</div>;
  }

  const hasImg = looksLikeHttpUrl(product.imageUrl);

  function handleBuyNow() {
    if (!looksLikeHttpUrl(product!.affiliateUrl)) {
      alert('Invalid affiliate link.');
      return;
    }
    setConfirmOpen(true);
  }

  function confirmContinue() {
    setConfirmOpen(false);
    window.open(product!.affiliateUrl, '_blank', 'noopener,noreferrer');
  }

  return (
    <div className="max-w-2xl mx-auto space-y-4 pb-20">
      <button onClick={() => router.back()} className="p-2.5 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
        <ArrowLeft className="w-5 h-5 text-white" />
      </button>

      <Glass className="p-2 overflow-hidden">
        <div className="aspect-[1.1] rounded-2xl overflow-hidden bg-brand-surfaceDark flex items-center justify-center">
          {hasImg ? (
            <img src={product.imageUrl} alt={product.name} className="w-full h-full object-cover" />
          ) : (
            <ImageOff className="w-12 h-12 text-gray-600" />
          )}
        </div>
      </Glass>

      <Glass className="p-5 space-y-3">
        <h1 className="text-2xl font-black text-white leading-tight">{product.name || 'Untitled product'}</h1>
        <p className="text-2xl font-black text-brand-lime">{product.price || '—'}</p>
        <div className="border-t border-white/10 pt-3">
          <p className="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1.5">Description</p>
          <p className="text-sm text-gray-300 leading-relaxed whitespace-pre-wrap">{product.description || 'No description.'}</p>
        </div>
      </Glass>

      <button
        onClick={handleBuyNow}
        className="w-full py-4 bg-brand-lime text-brand-navy font-black rounded-2xl hover:brightness-110 transition-all flex items-center justify-center gap-2 text-sm tracking-wide"
      >
        <ShoppingCart className="w-5 h-5" /> BUY NOW
      </button>

      {confirmOpen && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm p-4" onClick={() => setConfirmOpen(false)}>
          <div onClick={(e) => e.stopPropagation()} className="w-full max-w-sm bg-[#0B1221] border border-white/10 rounded-3xl p-6 text-center">
            <div className="w-14 h-14 mx-auto rounded-full bg-brand-lime/10 flex items-center justify-center mb-4">
              <ExternalLink className="w-6 h-6 text-brand-lime" />
            </div>
            <h2 className="text-lg font-black text-white mb-2">Continue to Partner Store?</h2>
            <p className="text-sm text-gray-400 mb-6">You will be redirected to an external store to complete your purchase.</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmOpen(false)} className="flex-1 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white font-bold transition-colors">
                Cancel
              </button>
              <button onClick={confirmContinue} className="flex-1 py-3 rounded-xl bg-brand-lime text-brand-navy font-black hover:brightness-110 transition-all">
                Continue
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
