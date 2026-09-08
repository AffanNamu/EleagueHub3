import { CreditCard, Smartphone } from 'lucide-react';
import { formatNumber } from '@/lib/utils';
import type { ProviderUserCounts } from '@/lib/repositories/paymentsAdminRepository';

export function ProviderBreakdownCard({ counts }: { counts: ProviderUserCounts }) {
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div className="panel flex items-center gap-3 p-4">
        <div className="flex h-9 w-9 items-center justify-center rounded-md bg-brand-faint text-brand">
          <CreditCard size={17} />
        </div>
        <div>
          <p className="text-xs text-ink-muted">Registered via Flutterwave</p>
          <p className="font-display text-xl font-semibold text-ink-primary">
            {formatNumber(counts.flutterwave)}
          </p>
        </div>
      </div>

      <div className="panel flex items-center gap-3 p-4">
        <div className="flex h-9 w-9 items-center justify-center rounded-md bg-signal-successFaint text-signal-success">
          <Smartphone size={17} />
        </div>
        <div>
          <p className="text-xs text-ink-muted">Registered via Google Play Billing</p>
          <p className="font-display text-xl font-semibold text-ink-primary">
            {formatNumber(counts.googlePlay)}
          </p>
        </div>
      </div>
    </div>
  );
}
