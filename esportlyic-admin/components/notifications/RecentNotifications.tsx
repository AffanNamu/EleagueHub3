import { Bell } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { formatRelativeTime } from '@/lib/utils';
import type { AuditLogEntry } from '@/types/auditLog';

export function RecentNotifications({ entries }: { entries: AuditLogEntry[] }) {
  if (entries.length === 0) {
    return <EmptyState icon={Bell} title="No notifications sent yet" />;
  }

  return (
    <div className="panel overflow-hidden">
      <div className="border-b border-base-border px-4 py-3">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Recently Sent</h2>
      </div>
      <ul className="divide-y divide-base-border">
        {entries.map((entry) => (
          <li key={entry.id} className="px-4 py-3">
            <p className="text-sm text-ink-primary">{entry.summary}</p>
            <p className="mt-1 text-xs text-ink-muted">
              {entry.actorEmail || entry.actorUid} · {entry.createdAtMs ? formatRelativeTime(entry.createdAtMs) : '—'}
            </p>
          </li>
        ))}
      </ul>
    </div>
  );
}
