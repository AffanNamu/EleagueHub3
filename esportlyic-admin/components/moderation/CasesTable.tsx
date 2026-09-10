import Link from 'next/link';
import { FolderSearch } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { formatRelativeTime } from '@/lib/utils';
import type { CaseStatus, ModerationCase } from '@/types/moderationCase';

const STATUS_TONE: Record<CaseStatus, 'warning' | 'info' | 'success' | 'neutral' | 'danger'> = {
  open: 'warning',
  investigating: 'info',
  resolved: 'success',
  dismissed: 'neutral',
  appealed: 'danger',
};

export function CasesTable({ cases }: { cases: ModerationCase[] }) {
  if (cases.length === 0) {
    return <EmptyState icon={FolderSearch} title="No cases in this view" />;
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Case</th>
            <th className="px-4 py-3 font-medium">Evidence</th>
            <th className="px-4 py-3 font-medium">Status</th>
            <th className="px-4 py-3 font-medium">Opened</th>
          </tr>
        </thead>
        <tbody>
          {cases.map((c) => (
            <tr key={c.caseId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <Link href={`/moderation/cases/${c.caseId}`}>
                  <p className="font-medium text-ink-primary">{c.targetUserName || c.targetUserId}</p>
                  <p className="text-xs text-ink-secondary">{c.reason}</p>
                </Link>
              </td>
              <td className="px-4 py-3 text-ink-secondary">{c.linkedEvidence.length} item(s)</td>
              <td className="px-4 py-3">
                <Badge tone={STATUS_TONE[c.status]} className="capitalize">{c.status}</Badge>
              </td>
              <td className="px-4 py-3 text-ink-secondary">
                {c.openedAtMs ? formatRelativeTime(c.openedAtMs) : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
