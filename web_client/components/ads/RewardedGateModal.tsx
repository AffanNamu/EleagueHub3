'use client';

import { useState } from 'react';
import { AdSlot } from './AdSlot';
import { Glass } from '@/components/ui/Glass';
import { Loader2, X } from 'lucide-react';

/**
 * AdSense has no native "rewarded video" primitive like AdMob's rewarded
 * ads — that's a mobile-SDK-only concept. The web-equivalent pattern most
 * sites use is: show a display ad in a modal, require a short minimum
 * dwell time (e.g. 15s) before unlocking the action, so free users still
 * see monetized inventory before proceeding. That's what this implements.
 *
 * FLAG: if you actually have a specific AdSense "Rewarded ads for web"
 * unit type enabled on your account (Google does offer this in some
 * regions via a different embed), tell me and I'll swap this for the
 * real rewarded unit instead of the dwell-timer approximation.
 */
export function RewardedGateModal({
  open,
  onClose,
  onUnlocked,
  adSlot,
  minDwellSeconds = 15,
}: {
  open: boolean;
  onClose: () => void;
  onUnlocked: () => void;
  adSlot: string;
  minDwellSeconds?: number;
}) {
  const [secondsLeft, setSecondsLeft] = useState(minDwellSeconds);

  if (!open) return null;

  // Countdown starts once on mount; re-open remounts this component.
  if (secondsLeft === minDwellSeconds) {
    setTimeout(() => {
      const tick = setInterval(() => {
        setSecondsLeft((s) => {
          if (s <= 1) {
            clearInterval(tick);
            return 0;
          }
          return s - 1;
        });
      }, 1000);
    }, 0);
  }

  const unlocked = secondsLeft <= 0;

  return (
    <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
      <Glass className="max-w-md w-full p-6 relative">
        <button onClick={onClose} className="absolute top-4 right-4 text-gray-400 hover:text-white">
          <X className="w-5 h-5" />
        </button>

        <h2 className="text-xl font-black text-white mb-2">Unlock for Free</h2>
        <p className="text-sm text-gray-400 mb-4">
          Free plan users can create this by viewing a quick sponsor message.
        </p>

        <div className="bg-brand-surfaceDark rounded-xl overflow-hidden min-h-[250px] flex items-center justify-center mb-4">
          <AdSlot slot={adSlot} className="w-full" />
        </div>

        <button
          onClick={onUnlocked}
          disabled={!unlocked}
          className="w-full py-3 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {unlocked ? 'Continue' : (
            <>
              <Loader2 className="w-4 h-4 animate-spin" /> Please wait {secondsLeft}s...
            </>
          )}
        </button>
      </Glass>
    </div>
  );
}
