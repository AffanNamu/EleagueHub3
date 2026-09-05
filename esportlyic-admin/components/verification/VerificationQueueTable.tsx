import Link from 'next/link';
import { Badge } from '@/components/ui/Badge';
import { formatRelativeTime } from '@/lib/utils';
import { isLegacyPaymentOnly, requestTypeLabel, verificationStatusLabel, verificationStatusTone } from '@/lib/models/masterLeagueVerification';
import type { VerificationRequest } from '@/types/verification';

export function VerificationQueueTable({ requests }: { requests: VerificationRequest[] }) {
  if (requests.length === 0) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">No verification requests in this view.</p>
      </div>
    );
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Organizer</th>
            <th className="px-4 py-3 font-medium">Type</th>
            <th className="px-4 py-3 font-medium">Status</th>
            <th className="px-4 py-3 font-medium">Submitted</th>
          </tr>
        </thead>
        <tbody>
          {requests.map((request) => {
            const legacy = isLegacyPaymentOnly(request);
            return (
              <tr key={request.requestId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                <td className="px-4 py-3">
                  <Link href={`/verification/${request.requestId}`} className="block">
                    <p className="font-medium text-ink-primary">
                      {legacy ? 'Legacy request (payment only)' : request.orgName || 'Untitled organization'}
                    </p>
                    <p className="text-xs text-ink-muted">{request.masterLeagueId}</p>
                  </Link>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{requestTypeLabel(request.requestType)}</td>
                <td className="px-4 py-3">
                  <Badge tone={verificationStatusTone(request.status)}>
                    {verificationStatusLabel(request.status)}
                  </Badge>
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {request.submittedAtMs ? formatRelativeTime(request.submittedAtMs) : '—'}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
