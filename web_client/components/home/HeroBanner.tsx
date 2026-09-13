'use client';

import Link from 'next/link';
import Image from 'next/image';
import { ArrowRight, Radio } from 'lucide-react';
import type { HomeContentItem } from '@/lib/social/homeContentRepository';

/** Admin-controlled hero slot (home_content, type: 'hero'). Renders nothing when there's no active hero — no fallback fake content. */
export function HeroBanner({ items }: { items: HomeContentItem[] }) {
  const hero = items[0];
  if (!hero) return null;

  return (
    <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#0B1221] to-[#070B14] border border-[#1E293B] p-8 group">
      {hero.imageUrl && (
        <div className="absolute inset-0">
          <Image src={hero.imageUrl} alt="" fill className="object-cover opacity-30" />
          <div className="absolute inset-0 bg-gradient-to-r from-[#070B14] via-[#070B14]/80 to-transparent" />
        </div>
      )}
      <div className="absolute top-0 right-0 w-64 h-64 bg-brand-lime/10 blur-[80px] rounded-full pointer-events-none group-hover:bg-brand-lime/20 transition-all duration-700" />
      <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div className="space-y-4 max-w-lg">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-brand-lime/10 border border-brand-lime/20 text-brand-lime text-xs font-black uppercase tracking-widest">
            <Radio className="w-3 h-3 animate-pulse" /> eSportlyic
          </div>
          <h2 className="text-3xl md:text-4xl font-black text-white tracking-tight leading-tight">{hero.title}</h2>
          {hero.subtitle && <p className="text-gray-400 font-medium">{hero.subtitle}</p>}
          {hero.ctaRoute && hero.ctaLabel && (
            <div className="pt-2">
              <Link
                href={hero.ctaRoute}
                className="inline-flex items-center gap-2 px-6 py-3 bg-brand-lime text-[#070B14] font-black rounded-xl hover:brightness-110 transition-all shadow-[0_0_20px_rgba(182,255,0,0.15)]"
              >
                {hero.ctaLabel} <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
