import { ScrollText } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { formatRelativeTime } from '@/lib/utils';
import type { AuditLogEntry } from '@/types/auditLog';

const ACTION_TONE: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'neutral'> = {
  approve: 'success',
  reject: 'danger',
  dismiss: 'neutral',
  request_info: 'warning',
  moderate: 'warning',
  create: 'info',
  update: 'info',
  delete: 'danger',
  add: 'info',
  remove: 'danger',
};

function toneForAction(action: string) {
  const verb = action.split('.').pop() ?? '';
  return ACTION_TONE[verb] ?? 'neutral';
}

export function AuditLogTable({ entries }: { entries: AuditLogEntry[] }) {
  if (entries.length === 0) {
    return (
      <EmptyState
        icon={ScrollText}
        title="No audit log entries yet"
        description="Actions taken across this workspace — verification decisions, report reviews, moderation, and admin/role changes — will appear here as they happen."
      />
    );
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Action</th>
            <th className="px-4 py-3 font-medium">Actor</th>
            <th className="px-4 py-3 font-medium">When</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <div className="flex items-center gap-2">
                  <Badge tone={toneForAction(entry.action)} className="font-mono text-[11px]">
                    {entry.action}
                  </Badge>
                </div>
                <p className="mt-1 text-sm text-ink-primary">{entry.summary}</p>
              </td>
              <td className="px-4 py-3 text-ink-secondary">{entry.actorEmail || entry.actorUid}</td>
              <td className="px-4 py-3 text-ink-secondary">
                {entry.createdAtMs ? formatRelativeTime(entry.createdAtMs) : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
