import { Gamepad2, Smartphone, CircleDot, type LucideIcon } from 'lucide-react';

// Direct TS port of lib/features/leagues/models/football_category.dart.
// Exactly 6 supported categories — do not add more without updating Flutter too.

export type FootballCategory =
  | 'localFootball'
  | 'eFootball'
  | 'eaSportsFC'
  | 'eaSportsFCMobile'
  | 'dreamLeagueSoccer'
  | 'totalFootball';

interface CategoryMeta {
  storageValue: string;
  emoji: string;
  icon: LucideIcon;
}

// lucide-react@0.383.0 has no dedicated "football" icon; CircleDot stands in
// for the ⚽ categories, Gamepad2/Smartphone for the game-console ones —
// the emoji (matching Dart exactly) carries the actual meaning.
const CATEGORY_META: Record<FootballCategory, CategoryMeta> = {
  localFootball: { storageValue: 'Local Football', emoji: '⚽', icon: CircleDot },
  eFootball: { storageValue: 'eFootball', emoji: '🎮', icon: Gamepad2 },
  eaSportsFC: { storageValue: 'EA SPORTS FC', emoji: '🎮', icon: Gamepad2 },
  eaSportsFCMobile: { storageValue: 'EA SPORTS FC Mobile', emoji: '📱', icon: Smartphone },
  dreamLeagueSoccer: { storageValue: 'Dream League Soccer', emoji: '⚽', icon: CircleDot },
  totalFootball: { storageValue: 'Total Football', emoji: '🎮', icon: Gamepad2 },
};

// Fixed product-spec order — mirrors `FootballCategory.values` in Dart.
export const ALL_FOOTBALL_CATEGORIES: FootballCategory[] = [
  'localFootball',
  'eFootball',
  'eaSportsFC',
  'eaSportsFCMobile',
  'dreamLeagueSoccer',
  'totalFootball',
];

export function categoryStorageValue(c: FootballCategory): string {
  return CATEGORY_META[c].storageValue;
}

export function categoryLabel(c: FootballCategory): string {
  return CATEGORY_META[c].storageValue;
}

export function categoryEmoji(c: FootballCategory): string {
  return CATEGORY_META[c].emoji;
}

export function categoryBadgeLabel(c: FootballCategory): string {
  return `${categoryEmoji(c)} ${categoryLabel(c)}`;
}

export function categoryIcon(c: FootballCategory): LucideIcon {
  return CATEGORY_META[c].icon;
}

/**
 * Null-safe parser. Mirrors FootballCategoryUtil.fromStorage exactly:
 * any missing/unrecognized value resolves to Local Football, so old league
 * documents without `footballCategory` need no migration.
 */
export function footballCategoryFromStorage(raw: string | undefined | null): FootballCategory {
  const s = (raw ?? '').trim();
  if (!s) return 'localFootball';
  const found = ALL_FOOTBALL_CATEGORIES.find((c) => CATEGORY_META[c].storageValue === s);
  return found ?? 'localFootball';
}
