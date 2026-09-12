'use client';

import { useState } from 'react';
import { X, Loader2, Flag } from 'lucide-react';
import {
  USER_REPORT_REASONS,
  userReportReasonLabel,
  submitReportWeb,
} from '@/lib/profile/teamProfileRepository';

interface ReportUserModalProps {
  targetUserId: string;
  onClose: () => void;
  onSubmitted: () => void;
}

// Mirrors the "Report user" bottom sheet in
// lib/features/profile/presentation/public_team_profile_screen.dart —
// same reasons, same optional details field, same submit-once behavior.
export function ReportUserModal({ targetUserId, onClose, onSubmitted }: ReportUserModalProps) {
  const [reason, setReason] = useState<string | null>(null);
  const [details, setDetails] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!reason || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await submitReportWeb({ targetUserId, reason, details });
      onSubmitted();
    } catch (err) {
      setSubmitting(false);
      setError(err instanceof Error ? err.message : 'Could not submit report.');
    }
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div className="w-full max-w-sm bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 relative shadow-2xl">
        <button
          onClick={onClose}
          disabled={submitting}
          className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-lg font-black text-white mb-4 flex items-center gap-2">
          <Flag className="w-4 h-4 text-red-500" /> Report user
        </h3>

        <div className="flex flex-wrap gap-2 mb-4">
          {USER_REPORT_REASONS.map((r) => (
            <button
              key={r}
              onClick={() => setReason(r)}
              disabled={submitting}
              className={`px-3 py-1.5 rounded-full text-xs font-bold border transition-colors disabled:opacity-50 ${
                reason === r
                  ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]'
                  : 'bg-white/[0.03] text-slate-300 border-white/10 hover:bg-white/10'
              }`}
            >
              {userReportReasonLabel(r)}
            </button>
          ))}
        </div>

        <textarea
          value={details}
          disabled={submitting}
          onChange={(e) => setDetails(e.target.value.slice(0, 500))}
          maxLength={500}
          rows={3}
          placeholder="Additional details (optional)"
          className="w-full px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40 disabled:opacity-60 resize-none mb-4"
        />

        {error && <div className="text-xs font-bold text-red-400 mb-3">{error}</div>}

        <button
          onClick={handleSubmit}
          disabled={!reason || submitting}
          className="w-full py-2.5 rounded-xl bg-red-500 text-white text-sm font-black hover:brightness-110 transition-all disabled:opacity-40 flex items-center justify-center gap-2"
        >
          {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Submit Report'}
        </button>
      </div>
    </div>
  );
}
