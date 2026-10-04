'use client';

import { useEffect, useRef, useState } from 'react';
import { SmilePlus } from 'lucide-react';
import { REACTION_EMOJIS } from '@/types/reactions';
import { cn } from '@/lib/utils';

interface ReactionPickerProps {
  currentEmoji?: string | null;
  onPick: (emoji: string) => void;
  /** Extra classes for the trigger button (e.g. to resize/recolor it). */
  className?: string;
}

/**
 * Smiley trigger button that opens a small emoji-row popover. Picking an
 * emoji calls onPick and closes the popover. Mirrors
 * lib/core/reactions/presentation/reaction_picker.dart (a bottom sheet on
 * mobile; a popover is the natural web equivalent of the same picker).
 */
export function ReactionPicker({ currentEmoji, onPick, className }: ReactionPickerProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onClickOutside = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, [open]);

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        title="React"
        className={cn('p-1 text-gray-500 hover:text-sky-400 transition-colors', className)}
      >
        <SmilePlus className="w-3.5 h-3.5" />
      </button>
      {open && (
        <div className="absolute z-50 bottom-full mb-2 left-0 flex items-center gap-1 px-2 py-1.5 rounded-full bg-[#0B1221] border border-white/10 shadow-xl whitespace-nowrap">
          {REACTION_EMOJIS.map((emoji) => (
            <button
              key={emoji}
              type="button"
              onClick={() => {
                onPick(emoji);
                setOpen(false);
              }}
              className={cn(
                'w-7 h-7 flex items-center justify-center rounded-full text-lg hover:scale-125 transition-transform',
                currentEmoji === emoji && 'bg-brand-lime/20 ring-1 ring-brand-lime/60'
              )}
            >
              {emoji}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
