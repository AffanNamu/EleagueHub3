import { cn } from '@/lib/utils';

type BadgeTone = 'neutral' | 'brand' | 'success' | 'warning' | 'danger' | 'info';

const TONE_CLASSES: Record<BadgeTone, string> = {
  neutral: 'bg-base-raised text-ink-secondary border-base-border',
  brand: 'bg-brand-faint text-brand border-brand/30',
  success: 'bg-signal-successFaint text-signal-success border-signal-success/30',
  warning: 'bg-signal-warningFaint text-signal-warning border-signal-warning/30',
  danger: 'bg-signal-dangerFaint text-signal-danger border-signal-danger/30',
  info: 'bg-signal-infoFaint text-signal-info border-signal-info/30',
};

export function Badge({
  children,
  tone = 'neutral',
  className,
}: {
  children: React.ReactNode;
  tone?: BadgeTone;
  className?: string;
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-sm border px-2 py-0.5 text-xs font-medium',
        TONE_CLASSES[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
