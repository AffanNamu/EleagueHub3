import type { LucideIcon } from 'lucide-react';

export function EmptyState({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description?: string;
}) {
  return (
    <div className="panel flex flex-col items-center justify-center gap-2 p-10 text-center">
      <div className="flex h-10 w-10 items-center justify-center rounded-md bg-base-raised text-ink-secondary">
        <Icon size={18} />
      </div>
      <p className="text-sm font-medium text-ink-primary">{title}</p>
      {description && <p className="max-w-sm text-sm text-ink-secondary">{description}</p>}
    </div>
  );
}
