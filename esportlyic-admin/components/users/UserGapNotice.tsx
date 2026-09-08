import { Info } from 'lucide-react';
import { formatNumber } from '@/lib/utils';

export function UserGapNotice({ authCount, profileCount }: { authCount: number; profileCount: number }) {
  const gap = authCount - profileCount;

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div className="panel p-4">
        <p className="text-xs text-ink-muted">Firebase Auth Accounts (all sign-ups)</p>
        <p className="mt-1 font-display text-xl font-semibold text-ink-primary">{formatNumber(authCount)}</p>
      </div>
      <div className="panel p-4">
        <p className="text-xs text-ink-muted">Firestore Profiles (completed onboarding)</p>
        <p className="mt-1 font-display text-xl font-semibold text-ink-primary">{formatNumber(profileCount)}</p>
      </div>

      {gap > 0 && (
        <div className="sm:col-span-2">
          <div className="flex items-start gap-2 rounded-sm border border-signal-info/30 bg-signal-infoFaint px-3 py-2.5">
            <Info size={15} className="mt-0.5 flex-shrink-0 text-signal-info" />
            <p className="text-sm text-ink-secondary">
              <span className="font-medium text-ink-primary">{formatNumber(gap)}</span>{' '}
              {gap === 1 ? 'person has' : 'people have'} signed up but never completed onboarding
              (no profile was created), so they don't appear in the list below. This is a real
              drop-off gap, not a dashboard limitation.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
