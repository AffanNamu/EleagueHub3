'use client';

import Image from 'next/image';
import { MessageCircle, CheckCircle2, XCircle } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useGlobalChatRequestAction } from '@/hooks/useGlobalChatRequestAction';
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

  if (requests.length === 0) {
    return <EmptyState icon={MessageCircle} title="No requests in this view" />;
  }

  return (
    <div className="space-y-3">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-base-border text-left text-xs text-ink-muted">
              <th className="px-4 py-3 font-medium">User</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Requested</th>
              {canReview && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {requests.map((request) => (
              <tr key={request.uid} className="border-b border-base-border last:border-0 hover:bg-base-raised">
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
