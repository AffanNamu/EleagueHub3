'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { UserCog, ShieldAlert, Trash2, ScrollText } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { formatRelativeTime } from '@/lib/utils';
import type { MasterLeagueStaffMember, MasterLeagueStaffAuditEntry } from '@/types/masterLeagueStaff';

const ROLE_TONE: Record<string, 'brand' | 'info' | 'warning' | 'neutral'> = {
  owner: 'brand',
  admin: 'info',
  result_manager: 'neutral',
  moderator: 'warning',
};

function Avatar({ name, photoUrl }: { name: string; photoUrl: string }) {
  if (photoUrl) {
    return (
      <Image
        src={photoUrl}
        alt={name}
        width={32}
        height={32}
        className="rounded-full border border-base-border object-cover"
      />
    );
  }
  return (
    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-base-raised text-xs font-semibold text-ink-secondary">
      {name.slice(0, 1).toUpperCase() || '?'}
    </div>
  );
}

export function MasterLeagueStaffPanel({
  organizerId,
  staff,
  auditLog,
  canManage,
}: {
  organizerId: string;
  staff: MasterLeagueStaffMember[];
  auditLog: MasterLeagueStaffAuditEntry[];
  canManage: boolean;
}) {
  const router = useRouter();
  const [tab, setTab] = useState<'staff' | 'activity'>('staff');
  const [error, setError] = useState<string | null>(null);
  const [removingUid, setRemovingUid] = useState<string | null>(null);

  async function handleRemove(member: MasterLeagueStaffMember) {
    if (!confirm(`Remove ${member.displayName} as ${member.roleLabel} from this workspace?`)) return;

    setError(null);
    setRemovingUid(member.uid);
    try {
      const response = await fetch(`/api/admin/organizers/${organizerId}/staff/${member.uid}`, {
        method: 'DELETE',
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Could not remove this staff member.');
        return;
      }
      router.refresh();
    } finally {
      setRemovingUid(null);
    }
  }

  return (
    <div className="panel p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Staff</h2>
        <div className="flex gap-1 rounded-md bg-base-raised p-1">
          <button
            onClick={() => setTab('staff')}
            className={`flex items-center gap-1.5 rounded-sm px-2.5 py-1 text-xs font-medium ${
              tab === 'staff' ? 'bg-brand text-base' : 'text-ink-secondary hover:text-ink-primary'
            }`}
          >
            <UserCog size={13} /> Staff ({staff.length})
          </button>
          <button
            onClick={() => setTab('activity')}
            className={`flex items-center gap-1.5 rounded-sm px-2.5 py-1 text-xs font-medium ${
              tab === 'activity' ? 'bg-brand text-base' : 'text-ink-secondary hover:text-ink-primary'
            }`}
          >
            <ScrollText size={13} /> Activity Log
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-3 flex items-center gap-2 rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          <ShieldAlert size={14} /> {error}
        </div>
      )}

      {tab === 'staff' ? (
        staff.length === 0 ? (
          <EmptyState icon={UserCog} title="No staff" description="This workspace has no owner or staff on record." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                  <th className="py-2 pr-3 font-medium">Member</th>
                  <th className="py-2 pr-3 font-medium">Role</th>
                  <th className="py-2 pr-3 font-medium">Scope</th>
                  {canManage && <th className="py-2 pr-0 font-medium" />}
                </tr>
              </thead>
              <tbody>
                {staff.map((member) => (
                  <tr key={member.uid} className="border-b border-base-border last:border-0">
                    <td className="py-2.5 pr-3">
                      <div className="flex items-center gap-2.5">
                        <Avatar name={member.displayName} photoUrl={member.photoUrl} />
                        <div>
                          <p className="font-medium text-ink-primary">{member.displayName}</p>
                          <p className="text-xs text-ink-muted">{member.uid}</p>
                        </div>
                      </div>
                    </td>
                    <td className="py-2.5 pr-3">
                      <Badge tone={ROLE_TONE[member.role] ?? 'neutral'}>{member.roleLabel}</Badge>
                    </td>
                    <td className="py-2.5 pr-3 text-ink-secondary">
                      {member.isOwner
                        ? 'All competitions'
                        : member.scopeLeagueIds.length === 0
                          ? 'All competitions'
                          : `${member.scopeLeagueIds.length} competition${member.scopeLeagueIds.length === 1 ? '' : 's'}`}
                    </td>
                    {canManage && (
                      <td className="py-2.5 pr-0 text-right">
                        {!member.isOwner && (
                          <button
                            onClick={() => handleRemove(member)}
                            disabled={removingUid === member.uid}
                            className="rounded-sm p-1.5 text-ink-secondary hover:bg-signal-dangerFaint hover:text-signal-danger disabled:opacity-50"
                            aria-label={`Remove ${member.displayName}`}
                          >
                            <Trash2 size={15} />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      ) : auditLog.length === 0 ? (
        <EmptyState
          icon={ScrollText}
          title="No staff activity yet"
          description="Staff additions, removals, and scope changes will appear here."
        />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                <th className="py-2 pr-3 font-medium">Action</th>
                <th className="py-2 pr-3 font-medium">By</th>
                <th className="py-2 pr-3 font-medium">Target</th>
                <th className="py-2 pr-3 font-medium">Details</th>
                <th className="py-2 pr-0 font-medium">When</th>
              </tr>
            </thead>
            <tbody>
              {auditLog.map((entry) => (
                <tr key={entry.id} className="border-b border-base-border last:border-0">
                  <td className="py-2.5 pr-3 text-ink-primary">{ACTION_LABELS[entry.action] ?? entry.action}</td>
                  <td className="py-2.5 pr-3 text-ink-secondary">{entry.performedByName}</td>
                  <td className="py-2.5 pr-3 text-ink-secondary">
                    {entry.targetUserName}
                    {entry.targetRole && <span className="text-ink-muted"> · {entry.targetRole}</span>}
                  </td>
                  <td className="py-2.5 pr-3 text-ink-secondary">{entry.details || '—'}</td>
                  <td className="py-2.5 pr-0 text-ink-muted">{formatRelativeTime(entry.performedAtMs)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

const ACTION_LABELS: Record<string, string> = {
  staff_added: 'Staff added',
  staff_removed: 'Staff removed',
  scope_changed: 'Scope changed',
};
