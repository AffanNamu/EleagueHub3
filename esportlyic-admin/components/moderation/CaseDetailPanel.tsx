'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Badge } from '@/components/ui/Badge';
import { useModerationCaseAction } from '@/hooks/useModerationCaseAction';
import { formatRelativeTime } from '@/lib/utils';
import type { CaseStatus, ModerationCase } from '@/types/moderationCase';

const STATUS_TONE: Record<CaseStatus, 'warning' | 'info' | 'success' | 'neutral' | 'danger'> = {
  open: 'warning',
  investigating: 'info',
  resolved: 'success',
  dismissed: 'neutral',
  appealed: 'danger',
};

const EVIDENCE_LINK: Record<string, (id: string) => string> = {
  report: (id) => `/moderation/reports/${id}`,
  global_chat_request: () => `/moderation/global-chat-requests`,
  post: (id) => `/content/posts/${id}`,
  discussion_thread: (id) => `/content/discussions/${id}`,
};

export function CaseDetailPanel({ caseData, canManage }: { caseData: ModerationCase; canManage: boolean }) {
  const { addNote, resolve, submitting, error } = useModerationCaseAction(caseData.caseId);
  const [noteText, setNoteText] = useState('');
  const [decision, setDecision] = useState(caseData.decision);
  const [actionTaken, setActionTaken] = useState(caseData.actionTaken);

  const isOpen = caseData.status === 'open' || caseData.status === 'investigating' || caseData.status === 'appealed';

  async function handleAddNote() {
    const ok = await addNote(noteText);
    if (ok) setNoteText('');
  }

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <div className="space-y-4 lg:col-span-2">
        <div className="panel p-5">
          <div className="mb-3 flex items-center justify-between">
            <div>
              <h1 className="font-display text-lg font-semibold text-ink-primary">
                {caseData.targetUserName || caseData.targetUserId}
              </h1>
              <p className="text-sm text-ink-secondary">{caseData.reason}</p>
            </div>
            <Badge tone={STATUS_TONE[caseData.status]} className="capitalize">{caseData.status}</Badge>
          </div>
          <p className="text-xs text-ink-muted">
            Opened by {caseData.openedByName || caseData.openedBy} · {formatRelativeTime(caseData.openedAtMs)}
          </p>
          <Link href={`/users/${caseData.targetUserId}`} className="mt-2 inline-block text-sm text-brand hover:underline">
            View user profile
          </Link>
        </div>

        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">
            Linked Evidence ({caseData.linkedEvidence.length})
          </h2>
          {caseData.linkedEvidence.length === 0 ? (
            <p className="text-sm text-ink-secondary">No evidence linked yet.</p>
          ) : (
            <ul className="space-y-1.5">
              {caseData.linkedEvidence.map((ev) => {
                const linkFn = EVIDENCE_LINK[ev.type];
                return (
                  <li key={`${ev.type}-${ev.id}`}>
                    {linkFn ? (
                      <Link href={linkFn(ev.id)} className="text-sm text-brand hover:underline">
                        {ev.label}
                      </Link>
                    ) : (
                      <span className="text-sm text-ink-secondary">{ev.label}</span>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Investigation Notes</h2>
          {error && (
            <div className="mb-3 rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
              {error}
            </div>
          )}
          <div className="mb-4 space-y-2">
            {caseData.notes.length === 0 ? (
              <p className="text-sm text-ink-secondary">No notes yet.</p>
            ) : (
              caseData.notes.map((note, i) => (
                <div key={i} className="rounded-sm bg-base-raised p-3">
                  <p className="text-sm text-ink-primary">{note.text}</p>
                  <p className="mt-1 text-xs text-ink-muted">
                    {note.authorName} · {formatRelativeTime(note.createdAtMs)}
                  </p>
                </div>
              ))
            )}
          </div>
          {canManage && isOpen && (
            <div className="flex gap-2">
              <textarea
                value={noteText}
                onChange={(e) => setNoteText(e.target.value)}
                rows={2}
                placeholder="Add an investigation note…"
                className="flex-1 rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
              />
              <button
                onClick={handleAddNote}
                disabled={submitting || !noteText.trim()}
                className="rounded-sm bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
              >
                Add
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="space-y-4">
        {canManage && isOpen ? (
          <div className="panel space-y-3 p-5">
            <h2 className="font-display text-sm font-semibold text-ink-primary">Resolve Case</h2>
            <textarea
              value={decision}
              onChange={(e) => setDecision(e.target.value)}
              rows={3}
              placeholder="Decision (e.g. 'Confirmed harassment, first offense')"
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            />
            <input
              value={actionTaken}
              onChange={(e) => setActionTaken(e.target.value)}
              placeholder="Action taken (e.g. '7-day chat ban')"
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            />
            <div className="space-y-1.5">
              <button
                onClick={() => resolve('resolved', decision, actionTaken)}
                disabled={submitting}
                className="w-full rounded-sm bg-signal-success py-2 text-sm font-medium text-base disabled:opacity-60"
              >
                Mark Resolved
              </button>
              <button
                onClick={() => resolve('dismissed', decision, actionTaken)}
                disabled={submitting}
                className="w-full rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-ink-muted disabled:opacity-60"
              >
                Dismiss Case
              </button>
            </div>
          </div>
        ) : (
          !isOpen && (
            <div className="panel p-5">
              <h2 className="mb-2 font-display text-sm font-semibold text-ink-primary">Decision</h2>
              <p className="text-sm text-ink-primary">{caseData.decision || '—'}</p>
              <p className="mt-2 text-xs text-ink-muted">Action Taken</p>
              <p className="text-sm text-ink-primary">{caseData.actionTaken || '—'}</p>
              <p className="mt-3 text-xs text-ink-muted">
                Resolved by {caseData.resolvedBy} · {formatRelativeTime(caseData.resolvedAtMs)}
              </p>
            </div>
          )
        )}
      </div>
    </div>
  );
}
