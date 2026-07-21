'use client';

import { FootballCategory, categoryEmoji, categoryLabel } from '@/lib/models/footballCategory';

export interface FootballCategoryChipProps {
  category: FootballCategory | null;
  selected: boolean;
  onClick: () => void;
}

export function FootballCategoryChip({ category, selected, onClick }: FootballCategoryChipProps) {
  const label = category === null ? 'All' : categoryLabel(category);
  const emoji = category === null ? null : categoryEmoji(category);

  return (
    <button
      type="button"
      onClick={onClick}
      className={`shrink-0 flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold border transition-all whitespace-nowrap ${
        selected
          ? 'bg-brand-lime border-brand-lime text-slate-900'
          : 'bg-white dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10'
      }`}
    >
      {emoji && <span>{emoji}</span>}
      {label}
    </button>
  );
}
