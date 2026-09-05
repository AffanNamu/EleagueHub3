import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatNumber } from '@/lib/utils';

type StatTone = 'brand' | 'success' | 'warning' | 'danger' | 'info';

const TONE_CLASSES: Record<StatTone, string> = {
  brand: 'bg-brand-faint text-brand',
  success: 'bg-signal-successFaint text-signal-success',
  warning: 'bg-signal-warningFaint text-signal-warning',
  danger: 'bg-signal-dangerFaint text-signal-danger',
  info: 'bg-signal-infoFaint text-signal-info',
};

export function StatCard({
  label,
  value,
  icon: Icon,
  tone = 'brand',
}: {
  label: string;
  value: number;
  icon: LucideIcon;
  tone?: StatTone;
}) {
  return (
    <div className="panel flex items-start justify-between p-4">
      <div>
        <p className="text-sm text-ink-secondary">{label}</p>
        <p className="mt-1.5 font-display text-2xl font-semibold text-ink-primary">
          {formatNumber(value)}
        </p>
      </div>
      <div className={cn('flex h-9 w-9 items-center justify-center rounded-md', TONE_CLASSES[tone])}>
        <Icon size={18} strokeWidth={2} />
      </div>
    </div>
  );
}
