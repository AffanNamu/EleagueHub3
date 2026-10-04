'use client';

import { ReactionSummary, orderedReactionEntries } from '@/types/reactions';
import { cn } from '@/lib/utils';

interface ReactionPillBarProps {
  summary: ReactionSummary;
  onTapEmoji: (emoji: string) => void;
}

/**
 * Row of emoji pills showing grouped reaction counts. Tapping a pill the
 * caller already reacted with removes it; tapping another emoji's pill
 * switches to it. Renders nothing when there are no reactions yet.
 * Mirrors lib/core/reactions/presentation/reaction_pill_bar.dart.
 */
export function ReactionPillBar({ summary, onTapEmoji }: ReactionPillBarProps) {
  const entries = orderedReactionEntries(summary);
  if (entries.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-1.5 mt-1">
      {entries.map(([emoji, count]) => {
        const isMine = summary.myEmoji === emoji;
        return (
          <button
            key={emoji}
            onClick={() => onTapEmoji(emoji)}
            className={cn(
              'flex items-center gap-1 px-2 py-0.5 rounded-full text-xs border transition-colors',
              isMine
                ? 'bg-brand-lime/20 border-brand-lime/60 text-brand-lime'
                : 'bg-white/5 border-white/10 text-gray-400 hover:bg-white/10'
            )}
          >
            <span>{emoji}</span>
            <span className="font-bold">{count}</span>
          </button>
        );
      })}
    </div>
  );
}
