'use client';

import { useState } from 'react';
import Image from 'next/image';
import { CheckCircle2, XCircle, MessageCircleQuestion } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { ReviewActionDialog } from '@/components/verification/ReviewActionDialog';
import { useVerificationReviewAction } from '@/hooks/useVerificationReviewAction';
import {
  isLegacyPaymentOnly,
  requestTypeLabel,
  verificationStatusLabel,
  verificationStatusTone,
} from '@/lib/models/masterLeagueVerification';
import { formatRelativeTime } from '@/lib/utils';
import type { MasterLeagueSummary, OwnerProfileSummary, ReviewAction, VerificationRequest } from '@/types/verification';

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-0.5 text-sm text-ink-primary">{value || '—'}</p>
    </div>
  );
}

export function VerificationReviewPanel({
  request,
  masterLeague,
  owner,
  canReview,
}: {
  request: VerificationRequest;
  masterLeague: MasterLeagueSummary | null;
  owner: OwnerProfileSummary | null;
  canReview: boolean;
}) {
  const [activeDialog, setActiveDialog] = useState<ReviewAction | null>(null);
  const { submit, submitting, error } = useVerificationReviewAction(request.requestId);

  const legacy = isLegacyPaymentOnly(request);
  const isReviewable =
    canReview && (request.status === 'pending' || request.status === 'info_requested');

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <div className="space-y-4 lg:col-span-2">
        <div className="panel p-5">
          <div className="mb-4 flex items-start justify-between">
            <div>
              <h1 className="font-display text-lg font-semibold text-ink-primary">
                {legacy ? 'Legacy request (payment only)' : request.orgName || 'Untitled organization'}
              </h1>
              <p className="mt-0.5 text-sm text-ink-secondary">{requestTypeLabel(request.requestType)}</p>
            </div>
            <Badge tone={verificationStatusTone(request.status)}>{verificationStatusLabel(request.status)}</Badge>
          </div>

          {legacy ? (
            <p className="rounded-sm bg-base-raised px-3 py-2.5 text-sm text-ink-secondary">
              This request was submitted before the application form existed. No organization
              details were collected — review the payment/receipt information and the linked
              organizer workspace before deciding.
            </p>
          ) : (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field label="Organization Type" value={request.orgType} />
              <Field label="Applicant" value={`${request.applicantFullName} (${request.applicantRole})`} />
              <Field label="Location" value={[request.orgCity, request.orgRegion, request.orgCountry].filter(Boolean).join(', ')} />
              <Field label="Contact Email" value={request.contactEmail} />
              <Field label="Contact Phone" value={request.contactPhone} />
              <Field label="Website" value={request.website} />
              <Field label="Social Link" value={request.socialLink} />
              <Field label="Competition Types" value={request.competitionTypes.join(', ')} />
              <div className="sm:col-span-2">
                <Field label="Organization Description" value={request.orgDescription} />
              </div>
              <div className="sm:col-span-2">
                <Field label="Reason for Verification" value={request.verificationReason} />
              </div>
              {request.supportingLinks.length > 0 && (
                <div className="sm:col-span-2">
                  <p className="text-xs text-ink-muted">Supporting Links</p>
                  <ul className="mt-1 space-y-0.5">
                    {request.supportingLinks.map((link) => (
                      <li key={link}>
                        <a href={link} target="_blank" rel="noreferrer" className="text-sm text-brand hover:underline">
                          {link}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Payment</h2>
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Field label="Provider" value={request.provider} />
            <Field label="Payment ID" value={request.paymentId} />
            <Field label="Receipt ID" value={request.receiptId} />
            <Field label="Attempt ID" value={request.attemptId} />
          </div>
        </div>

        {(request.status === 'approved' || request.status === 'rejected' || request.reviewedBy) && (
          <div className="panel p-5">
            <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Review History</h2>
            <Field label="Reviewed By" value={request.reviewedBy} />
            <div className="mt-3">
              <Field label="Note" value={request.note} />
            </div>
          </div>
        )}
      </div>

      <div className="space-y-4">
        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Organizer Workspace</h2>
          {masterLeague ? (
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                {masterLeague.logoUrl ? (
                  <Image
                    src={masterLeague.logoUrl}
                    alt={masterLeague.name}
                    width={40}
                    height={40}
                    className="rounded-sm border border-base-border object-cover"
                  />
                ) : (
                  <div className="flex h-10 w-10 items-center justify-center rounded-sm bg-base-raised text-xs text-ink-muted">
                    No logo
                  </div>
                )}
                <div>
                  <p className="text-sm font-medium text-ink-primary">{masterLeague.name}</p>
                  <p className="text-xs text-ink-muted uppercase">{masterLeague.plan} plan</p>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3 text-sm">
                <Field label="Tournaments" value={String(masterLeague.totalTournamentsCreated)} />
                <Field label="Followers" value={String(masterLeague.followersCount)} />
              </div>
              {masterLeague.verificationExpiresAtMs > 0 && (
                <Field
                  label="Current Verification Expires"
                  value={formatRelativeTime(masterLeague.verificationExpiresAtMs)}
                />
              )}
            </div>
          ) : (
            <p className="text-sm text-ink-secondary">Workspace not found.</p>
          )}
        </div>

        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Submitted By</h2>
          {owner ? (
            <div className="flex items-center gap-3">
              {owner.photoUrl ? (
                <Image
                  src={owner.photoUrl}
                  alt={owner.displayName}
                  width={36}
                  height={36}
                  className="rounded-full object-cover"
                />
              ) : (
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                  {owner.displayName.slice(0, 2).toUpperCase()}
                </div>
              )}
              <div>
                <p className="text-sm font-medium text-ink-primary">{owner.displayName}</p>
                <p className="text-xs text-ink-muted">{owner.userId}</p>
              </div>
            </div>
          ) : (
            <p className="text-sm text-ink-secondary">Owner profile not found.</p>
          )}
        </div>

        {isReviewable && (
          <div className="panel space-y-2 p-5">
            <h2 className="mb-1 font-display text-sm font-semibold text-ink-primary">Review Decision</h2>
            <button
              onClick={() => setActiveDialog('approve')}
              className="flex w-full items-center justify-center gap-2 rounded-sm bg-signal-success py-2 text-sm font-medium text-base"
            >
              <CheckCircle2 size={16} /> Approve
            </button>
            <button
              onClick={() => setActiveDialog('request_info')}
              className="flex w-full items-center justify-center gap-2 rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-signal-info"
            >
              <MessageCircleQuestion size={16} /> Request Info
            </button>
            <button
              onClick={() => setActiveDialog('reject')}
              className="flex w-full items-center justify-center gap-2 rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger"
            >
              <XCircle size={16} /> Reject
            </button>
          </div>
        )}
      </div>

      {activeDialog && (
        <ReviewActionDialog
          action={activeDialog}
          onClose={() => setActiveDialog(null)}
          onConfirm={(note) => submit(activeDialog, note)}
          submitting={submitting}
          error={error}
        />
      )}
    </div>
  );
}
