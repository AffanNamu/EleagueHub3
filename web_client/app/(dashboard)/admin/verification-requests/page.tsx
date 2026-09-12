'use client';

// Mirrors lib/features/admin/organizer_verification_requests_screen.dart —
// the admin-only review queue for master_league_verification_requests.
// Filter chips switch which status is streamed; each card exposes
// Approve / Request Info / Reject (pending + info_requested only), each
// backed by reviewVerificationRequestWeb's Firestore transaction.

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { isPricingAdminUid } from '@/lib/admin/appAdminsRepository';
import {
  useVerificationRequests,
  reviewVerificationRequestWeb,
  isLegacyPaymentOnly,
  OrganizerVerificationRequest,
  VerificationReviewAction,
} from '@/lib/masterLeagues/verificationRequestsRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, ShieldCheck, ShieldX, HelpCircle, ExternalLink, Copy, ShieldAlert } from 'lucide-react';

const FILTERS: { id: string; label: string }[] = [
  { id: 'pending', label: 'Pending' },
  { id: 'info_requested', label: 'Info Requested' },
  { id: 'approved', label: 'Approved' },
  { id: 'rejected', label: 'Rejected' },
];

const STATUS_COLORS: Record<string, string> = {
  approved: 'text-[#1D9BF0] bg-[#1D9BF0]/10 border-[#1D9BF0]/30',
  rejected: 'text-red-500 bg-red-500/10 border-red-500/30',
  info_requested: 'text-amber-500 bg-amber-500/10 border-amber-500/30',
  pending: 'text-amber-500 bg-amber-500/10 border-amber-500/30',
};

function Kv({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex gap-2 text-sm py-0.5">
      <span className="w-28 shrink-0 font-bold text-gray-500">{label}</span>
      <span className="text-gray-200 font-semibold break-words">{value}</span>
    </div>
  );
}

function dashIfEmpty(s: string): string {
  return s.trim().length ? s : '—';
}

export default function OrganizerVerificationRequestsPage() {
  const router = useRouter();
  const [authUid, setAuthUid] = useState<string | null | undefined>(undefined);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [filter, setFilter] = useState('pending');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [reviewFor, setReviewFor] = useState<{ req: OrganizerVerificationRequest; action: VerificationReviewAction } | null>(null);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');

  const { requests, loading } = useVerificationRequests(filter);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  useEffect(() => {
    if (authUid === undefined) return;
    let cancelled = false;
    isPricingAdminUid(authUid).then((ok) => {
      if (!cancelled) setIsAdmin(ok);
    });
    return () => {
      cancelled = true;
    };
  }, [authUid]);

  const openReview = (req: OrganizerVerificationRequest, action: VerificationReviewAction) => {
    setNote('');
    setError('');
    setReviewFor({ req, action });
  };

  const submitReview = async () => {
    if (!reviewFor || !authUid) return;
    const requiresNote = reviewFor.action !== 'approve';
    const trimmed = note.trim();
    if (requiresNote && !trimmed) {
      setError('A review note is required.');
      return;
    }

    setBusyId(reviewFor.req.requestId);
    setError('');
    try {
      await reviewVerificationRequestWeb({
        request: reviewFor.req,
        action: reviewFor.action,
        adminUid: authUid,
        note: trimmed,
      });
      setReviewFor(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Review failed.');
    } finally {
      setBusyId(null);
    }
  };

  if (isAdmin === null) {
    return (
      <div className="flex h-full items-center justify-center py-24">
        <Loader2 className="w-8 h-8 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  if (isAdmin === false) {
    return (
      <div className="max-w-2xl mx-auto text-center py-24">
        <ShieldAlert className="w-10 h-10 text-red-500 mx-auto mb-3" />
        <p className="text-red-500 font-black">Not authorized.</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6 pb-20 px-4 mt-6">
      <div className="flex items-center gap-4 mb-2">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-2xl font-black text-white">Verification Requests</h1>
      </div>

      <Glass className="p-5 bg-[#0B1221] border-[#1E293B] rounded-2xl space-y-3">
        <p className="text-white font-black">Review organizer verification applications</p>
        <div className="flex flex-wrap gap-2">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              onClick={() => setFilter(f.id)}
              className={`px-4 py-2 rounded-full text-xs font-black transition-colors ${
                filter === f.id
                  ? 'bg-[#BEF264] text-[#0F172A]'
                  : 'bg-[#070B14] border border-[#1E293B] text-gray-400 hover:text-white'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </Glass>

      {loading ? (
        <div className="flex justify-center py-16">
          <Loader2 className="w-8 h-8 animate-spin text-[#BEF264]" />
        </div>
      ) : requests.length === 0 ? (
        <div className="text-center py-10 font-bold text-gray-500 bg-[#0B1221] border border-[#1E293B] rounded-3xl">
          No {filter.replace('_', ' ')} verification applications found.
        </div>
      ) : (
        <div className="space-y-4">
          {requests.map((req) => {
            const statusColor = STATUS_COLORS[req.status] ?? STATUS_COLORS.pending;
            const legacy = isLegacyPaymentOnly(req);
            const canReview = req.status === 'pending' || req.status === 'info_requested';

            return (
              <Glass key={req.requestId} className="p-5 bg-[#0B1221] border-[#1E293B] rounded-2xl space-y-3">
                <div className="flex items-center gap-3 flex-wrap">
                  {req.logoUrl && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={req.logoUrl} alt="" className="w-9 h-9 rounded-full object-cover bg-gray-800" />
                  )}
                  <span className="font-black text-white text-base flex-1 min-w-0 truncate">
                    {req.orgName || (req.masterLeagueId ? `Master League: ${req.masterLeagueId}` : 'Verification Request')}
                  </span>
                  <span className="px-2.5 py-1 rounded-full text-[11px] font-black uppercase border border-[#BEF264]/30 bg-[#BEF264]/10 text-[#BEF264]">
                    {req.requestType}
                  </span>
                  <span className={`px-2.5 py-1 rounded-full text-[11px] font-black uppercase border ${statusColor}`}>
                    {req.status.replace('_', ' ')}
                  </span>
                </div>

                {legacy ? (
                  <p className="text-xs italic text-gray-500 font-semibold">
                    Legacy request — submitted before the application form existed. Payment info only.
                  </p>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6">
                    <Kv label="Org type" value={dashIfEmpty(req.orgType)} />
                    <Kv label="Country" value={dashIfEmpty(req.orgCountry)} />
                    <Kv label="Location" value={dashIfEmpty([req.orgCity, req.orgRegion].filter(Boolean).join(', '))} />
                    <Kv label="Applicant" value={dashIfEmpty(req.applicantFullName)} />
                    <Kv label="Role" value={dashIfEmpty(req.applicantRole)} />
                    <Kv label="Email" value={dashIfEmpty(req.contactEmail)} />
                    <Kv label="Phone" value={dashIfEmpty(req.contactPhone)} />
                    <Kv label="Website" value={dashIfEmpty(req.website)} />
                  </div>
                )}

                {req.orgDescription && (
                  <div>
                    <p className="text-xs font-black text-gray-500">What they do:</p>
                    <p className="text-sm text-gray-300 font-semibold">{req.orgDescription}</p>
                  </div>
                )}
                {req.verificationReason && (
                  <div>
                    <p className="text-xs font-black text-gray-500">Why they want verification:</p>
                    <p className="text-sm text-gray-300 font-semibold">{req.verificationReason}</p>
                  </div>
                )}
                {req.supportingLinks && (
                  <div>
                    <p className="text-xs font-black text-gray-500">Supporting links:</p>
                    <p className="text-sm text-gray-300 font-semibold break-words">{req.supportingLinks}</p>
                  </div>
                )}

                <div className="border-t border-[#1E293B] pt-3 space-y-0.5">
                  <Kv label="Request ID" value={req.requestId} />
                  <Kv label="Owner UID" value={req.ownerId} />
                  <Kv label="Provider" value={dashIfEmpty(req.provider)} />
                  <Kv label="Receipt ID" value={dashIfEmpty(req.receiptId)} />
                  <Kv label="Payment ID" value={dashIfEmpty(req.paymentId)} />
                  <Kv label="Submitted" value={req.submittedAtMs > 0 ? new Date(req.submittedAtMs).toLocaleString() : '—'} />
                  {req.resubmittedAtMs > 0 && <Kv label="Resubmitted" value={new Date(req.resubmittedAtMs).toLocaleString()} />}
                  {req.reviewedAtMs > 0 && <Kv label="Reviewed" value={new Date(req.reviewedAtMs).toLocaleString()} />}
                  {req.reviewedBy && <Kv label="Reviewed By" value={req.reviewedBy} />}
                </div>

                {req.note && (
                  <div>
                    <p className="text-xs font-black text-gray-500">Admin note:</p>
                    <p className="text-sm text-gray-300 font-semibold">{req.note}</p>
                  </div>
                )}

                <div className="flex flex-wrap gap-2 pt-2">
                  <button
                    disabled={!req.masterLeagueId}
                    onClick={() => router.push(`/master-leagues/${req.masterLeagueId}`)}
                    className="px-3 py-2 rounded-xl border border-[#1E293B] text-gray-300 text-xs font-black hover:text-white disabled:opacity-40 flex items-center gap-1.5"
                  >
                    <ExternalLink className="w-3.5 h-3.5" /> Open Master League
                  </button>
                  <button
                    disabled={!req.ownerId}
                    onClick={() => navigator.clipboard.writeText(req.ownerId)}
                    className="px-3 py-2 rounded-xl border border-[#1E293B] text-gray-300 text-xs font-black hover:text-white disabled:opacity-40 flex items-center gap-1.5"
                  >
                    <Copy className="w-3.5 h-3.5" /> Copy Owner UID
                  </button>

                  {canReview && (
                    <>
                      <button
                        disabled={busyId === req.requestId}
                        onClick={() => openReview(req, 'approve')}
                        className="px-4 py-2 rounded-xl bg-[#BEF264] text-[#0F172A] text-xs font-black hover:brightness-110 disabled:opacity-50 flex items-center gap-1.5"
                      >
                        <ShieldCheck className="w-4 h-4" /> {req.requestType === 'renewal' ? 'Approve Renewal' : 'Approve'}
                      </button>
                      <button
                        disabled={busyId === req.requestId}
                        onClick={() => openReview(req, 'info_requested')}
                        className="px-4 py-2 rounded-xl border border-[#1E293B] text-gray-200 text-xs font-black hover:text-white disabled:opacity-50 flex items-center gap-1.5"
                      >
                        <HelpCircle className="w-4 h-4" /> Request Info
                      </button>
                      <button
                        disabled={busyId === req.requestId}
                        onClick={() => openReview(req, 'reject')}
                        className="px-4 py-2 rounded-xl bg-red-500/10 text-red-500 text-xs font-black hover:bg-red-500/20 disabled:opacity-50 flex items-center gap-1.5"
                      >
                        <ShieldX className="w-4 h-4" /> {req.requestType === 'renewal' ? 'Reject Renewal' : 'Reject'}
                      </button>
                    </>
                  )}
                </div>
              </Glass>
            );
          })}
        </div>
      )}

      {reviewFor && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
          <Glass className="w-full max-w-md p-6 bg-[#0B1221] border-[#1E293B] rounded-2xl space-y-4">
            <h2 className="text-lg font-black text-white">
              {reviewFor.action === 'approve' && 'Approve verification'}
              {reviewFor.action === 'reject' && 'Reject verification'}
              {reviewFor.action === 'info_requested' && 'Request additional information'}
            </h2>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={4}
              autoFocus
              placeholder={reviewFor.action === 'approve' ? 'Review note (optional)' : 'Review note (required)'}
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-3 text-white text-sm focus:outline-none focus:border-[#BEF264] resize-none"
            />
            {error && <p className="text-red-500 text-sm font-bold">{error}</p>}
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setReviewFor(null)}
                className="px-4 py-2.5 rounded-xl text-gray-400 font-black text-sm hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={submitReview}
                disabled={busyId === reviewFor.req.requestId}
                className="px-5 py-2.5 rounded-xl bg-[#BEF264] text-[#0F172A] font-black text-sm hover:brightness-110 disabled:opacity-50 flex items-center gap-2"
              >
                {busyId === reviewFor.req.requestId && <Loader2 className="w-4 h-4 animate-spin" />}
                {reviewFor.action === 'approve' && 'Approve'}
                {reviewFor.action === 'reject' && 'Reject'}
                {reviewFor.action === 'info_requested' && 'Request Info'}
              </button>
            </div>
          </Glass>
        </div>
      )}
    </div>
  );
}
