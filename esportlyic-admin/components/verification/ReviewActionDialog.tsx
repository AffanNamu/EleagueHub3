'use client';

import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import type { ReviewAction } from '@/types/verification';

const COPY: Record<ReviewAction, { title: string; noteLabel: string; noteRequired: boolean; confirmLabel: string }> = {
  approve: {
    title: 'Approve Verification',
    noteLabel: 'Note (optional)',
    noteRequired: false,
    confirmLabel: 'Approve',
  },
  reject: {
    title: 'Reject Verification',
    noteLabel: 'Reason for rejection (shown to the organizer)',
    noteRequired: true,
    confirmLabel: 'Reject',
  },
  request_info: {
    title: 'Request More Information',
    noteLabel: 'What additional information is needed?',
    noteRequired: true,
    confirmLabel: 'Send Request',
  },
};

export function ReviewActionDialog({
  action,
  onClose,
  onConfirm,
  submitting,
  error,
}: {
  action: ReviewAction;
  onClose: () => void;
  onConfirm: (note: string) => void;
  submitting: boolean;
  error: string | null;
}) {
  const [note, setNote] = useState('');
  const copy = COPY[action];
  const canSubmit = !copy.noteRequired || note.trim().length > 0;

  return (
    <Modal title={copy.title} onClose={onClose}>
      <div className="space-y-3">
        {error && (
          <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
            {error}
          </div>
        )}

        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">{copy.noteLabel}</label>
          <textarea
            value={note}
            onChange={(event) => setNote(event.target.value)}
            rows={4}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            placeholder={copy.noteRequired ? 'Required' : 'Optional'}
          />
        </div>

        <div className="flex justify-end gap-2 pt-1">
          <button
            onClick={onClose}
            className="rounded-sm px-3 py-1.5 text-sm text-ink-secondary hover:bg-base-raised"
          >
            Cancel
          </button>
          <button
            onClick={() => onConfirm(note)}
            disabled={!canSubmit || submitting}
            className="rounded-sm bg-brand px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
          >
            {submitting ? 'Submitting…' : copy.confirmLabel}
          </button>
        </div>
      </div>
    </Modal>
  );
}
