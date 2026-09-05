// lib/models/content.ts

import type { PostType } from '@/types/content';

export function postTypeLabel(type: PostType): string {
  switch (type) {
    case 'text':
      return 'Text Post';
    case 'competition_promo':
      return 'Competition Promo';
    case 'match_result':
      return 'Match Result';
    default:
      return type;
  }
}
