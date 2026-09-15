'use client';

import { useState } from 'react';
import Image from 'next/image';
import { MessageCircle, CheckCircle2, XCircle } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useGlobalChatRequestAction } from '@/hooks/useGlobalChatRequestAction';
import { useBulkGlobalChatRequestReview } from '@/hooks/useBulkGlobalChatRequestReview';
import { formatRelativeTime } from '@/lib/utils';
import type { GlobalChatRequest, GlobalChatRequestStatus } from '@/types/globalChatRequest';

const STATUS_TONE: Record<GlobalChatRequestStatus, 'warning' | 'success' | 'danger'> = {
  pending: 'warning',
  approved: 'success',
  rejected: 'danger',
};

export function GlobalChatRequestsTable({
  requests,
  canReview,
}: {
  requests: GlobalChatRequest[];
  canReview: boolean;
}) {
  const { submit, pendingUid, error } = useGlobalChatRequestAction();
  const { submit: submitBulk, submitting: bulkSubmitting, error: bulkError } = useBulkGlobalChatRequestReview();
  const [selected, setSelected] = useState<Set<string>>(new Set());

  if (requests.length === 0) {
    return <EmptyState icon={MessageCircle} title="No requests in this view" />;
  }

  const pendingUids = requests.filter((r) => r.status === 'pending').map((r) => r.uid);
  const allPendingSelected = pendingUids.length > 0 && pendingUids.every((uid) => selected.has(uid));

  function toggleAll() {
    setSelected(allPendingSelected ? new Set() : new Set(pendingUids));
  }

  function toggleOne(uid: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });
  }

  async function handleBulk(decision: 'approved' | 'rejected') {
    const uids = Array.from(selected);
    if (uids.length === 0) return;
    if (!confirm(`${decision === 'approved' ? 'Approve' : 'Reject'} ${uids.length} selected request(s)?`)) return;
    const ok = await submitBulk(uids, decision);
    if (ok) setSelected(new Set());
  }

  return (
    <div className="space-y-3">
      {(error || bulkError) && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error || bulkError}
        </div>
      )}

      {canReview && selected.size > 0 && (
        <div className="flex items-center justify-between rounded-sm border border-brand/30 bg-brand-faint px-3 py-2">
          <p className="text-sm text-ink-primary">{selected.size} selected</p>
          <div className="flex items-center gap-2">
            <button
              onClick={() => handleBulk('approved')}
              disabled={bulkSubmitting}
              className="flex items-center gap-1.5 rounded-sm bg-signal-success px-3 py-1.5 text-xs font-medium text-base disabled:opacity-60"
            >
              <CheckCircle2 size={13} /> Approve
            </button>
            <button
              onClick={() => handleBulk('rejected')}
              disabled={bulkSubmitting}
              className="flex items-center gap-1.5 rounded-sm border border-base-border bg-base-raised px-3 py-1.5 text-xs font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger disabled:opacity-60"
            >
              <XCircle size={13} /> Reject
            </button>
          </div>
        </div>
      )}

      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-base-border text-left text-xs text-ink-muted">
              {canReview && (
                <th className="w-10 px-4 py-3">
                  {pendingUids.length > 0 && (
                    <input
                      type="checkbox"
                      checked={allPendingSelected}
                      onChange={toggleAll}
                      className="h-4 w-4 rounded-sm border-base-border accent-brand"
                      aria-label="Select all pending requests"
                    />
                  )}
                </th>
              )}
              <th className="px-4 py-3 font-medium">User</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Requested</th>
              {canReview && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {requests.map((request) => (
              <tr key={request.uid} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                {canReview && (
                  <td className="px-4 py-3">
                    {request.status === 'pending' && (
                      <input
                        type="checkbox"
                        checked={selected.has(request.uid)}
                        onChange={() => toggleOne(request.uid)}
                        className="h-4 w-4 rounded-sm border-base-border accent-brand"
                        aria-label={`Select request from ${request.userName || request.uid}`}
                      />
                    )}
                  </td>
                )}
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {request.userPhoto ? (
                      <Image
                        src={request.userPhoto}
                        alt={request.userName}
                        width={32}
                        height={32}
                        className="rounded-full object-cover"
                      />
                    ) : (
                      <div className="flex h-8 w-8 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                        {(request.userName || request.userId).slice(0, 2).toUpperCase()}
                      </div>
                    )}
                    <div>
                      <p className="font-medium text-ink-primary">{request.userName || 'Unknown user'}</p>
                      <p className="text-xs text-ink-muted">{request.userId}</p>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <Badge tone={STATUS_TONE[request.status]} className="capitalize">
                    {request.status}
                  </Badge>
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {request.createdAtMs ? formatRelativeTime(request.createdAtMs) : '—'}
                </td>
                {canReview && (
                  <td className="px-4 py-3">
                    {request.status === 'pending' && (
                      <div className="flex justify-end gap-1.5">
                        <button
                          onClick={() => submit(request.uid, 'approved')}
                          disabled={pendingUid === request.uid}
                          className="flex items-center gap-1 rounded-sm bg-signal-success px-2.5 py-1 text-xs font-medium text-base disabled:opacity-60"
                        >
                          <CheckCircle2 size={13} /> Approve
                        </button>
                        <button
                          onClick={() => submit(request.uid, 'rejected')}
                          disabled={pendingUid === request.uid}
                          className="flex items-center gap-1 rounded-sm border border-base-border bg-base-raised px-2.5 py-1 text-xs font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger disabled:opacity-60"
                        >
                          <XCircle size={13} /> Reject
                        </button>
                      </div>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
