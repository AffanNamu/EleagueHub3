'use client';

import Link from 'next/link';
import Image from 'next/image';
import { ChevronRight, Megaphone } from 'lucide-react';
import type { HomeContentItem } from '@/lib/social/homeContentRepository';

/** Admin-controlled promo card row (home_content, type: 'promo_card'). Renders nothing when there are no active cards. */
export function PromoStrip({ items }: { items: HomeContentItem[] }) {
  if (items.length === 0) return null;

  return (
    <div className="flex gap-3 overflow-x-auto pb-1 custom-scrollbar">
      {items.map((item) => {
        const cardClasses =
          'flex items-center gap-3 min-w-[280px] p-4 rounded-2xl bg-[#0B1221] border border-[#1E293B] hover:border-brand-lime/40 transition-all shrink-0';
        const content = (
          <>
            <div className="w-10 h-10 rounded-xl bg-brand-lime/10 border border-brand-lime/20 flex items-center justify-center shrink-0 overflow-hidden relative">
              {item.imageUrl ? (
                <Image src={item.imageUrl} alt="" fill className="object-cover" />
              ) : (
                <Megaphone className="w-5 h-5 text-brand-lime" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-bold text-white truncate">{item.title}</p>
              {item.subtitle && <p className="text-xs text-gray-500 truncate">{item.subtitle}</p>}
            </div>
            {item.ctaRoute && <ChevronRight className="w-4 h-4 text-gray-500 shrink-0" />}
          </>
        );

        return item.ctaRoute ? (
          <Link key={item.id} href={item.ctaRoute} className={cardClasses}>
            {content}
          </Link>
        ) : (
          <div key={item.id} className={cardClasses}>
            {content}
          </div>
        );
      })}
    </div>
  );
}
