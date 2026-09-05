'use client';

import Image from 'next/image';
import { Trash2 } from 'lucide-react';
import { useDiscussionModerationAction } from '@/hooks/useDiscussionModerationAction';
import { formatRelativeTime } from '@/lib/utils';
import type { DiscussionReply, DiscussionThread } from '@/types/discussion';

export function DiscussionDetailPanel({
  thread,
  replies,
  canModerate,
}: {
  thread: DiscussionThread;
  replies: DiscussionReply[];
  canModerate: boolean;
}) {
  const { removeThread, removeReply, pendingId, error } = useDiscussionModerationAction();

  return (
    <div className="space-y-4">
      <div className="panel p-5">
        {error && (
          <div className="mb-3 rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
            {error}
          </div>
        )}

        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            {thread.authorPhotoUrl ? (
              <Image src={thread.authorPhotoUrl} alt={thread.authorDisplayName} width={36} height={36} className="rounded-full object-cover" />
            ) : (
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                {thread.authorDisplayName.slice(0, 2).toUpperCase()}
              </div>
            )}
            <div>
              <p className="text-sm font-medium text-ink-primary">{thread.authorDisplayName || thread.authorId}</p>
              <p className="text-xs text-ink-muted">{formatRelativeTime(thread.createdAtMs)}</p>
            </div>
          </div>
          {canModerate && (
            <button
              onClick={() => removeThread(thread.threadId)}
              disabled={pendingId === thread.threadId}
              className="flex items-center gap-1.5 rounded-sm border border-base-border bg-base-raised px-3 py-1.5 text-xs font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger disabled:opacity-60"
            >
              <Trash2 size={13} /> Remove Thread
            </button>
          )}
        </div>

        <h1 className="mt-4 font-display text-lg font-semibold text-ink-primary">{thread.title}</h1>
        <p className="mt-2 whitespace-pre-wrap text-sm text-ink-primary">{thread.body}</p>
      </div>

      <div className="panel p-5">
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Replies ({replies.length})</h2>
        {replies.length === 0 ? (
          <p className="text-sm text-ink-secondary">No replies yet.</p>
        ) : (
          <div className="space-y-3">
            {replies.map((reply) => (
              <div key={reply.replyId} className="flex items-start gap-3 rounded-sm bg-base-raised p-3">
                {reply.authorPhotoUrl ? (
                  <Image src={reply.authorPhotoUrl} alt={reply.authorDisplayName} width={28} height={28} className="rounded-full object-cover" />
                ) : (
                  <div className="flex h-7 w-7 items-center justify-center rounded-full bg-base text-xs text-ink-muted">
                    {reply.authorDisplayName.slice(0, 2).toUpperCase()}
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-ink-primary">{reply.authorDisplayName || reply.authorId}</p>
                  <p className="mt-0.5 text-sm text-ink-secondary">{reply.text}</p>
                  <p className="mt-1 text-xs text-ink-muted">{formatRelativeTime(reply.createdAtMs)}</p>
                </div>
                {canModerate && (
                  <button
                    onClick={() => removeReply(thread.threadId, reply.replyId)}
                    disabled={pendingId === reply.replyId}
                    className="flex-shrink-0 rounded-sm p-1.5 text-ink-secondary hover:bg-base hover:text-signal-danger disabled:opacity-60"
                    aria-label="Remove reply"
                  >
                    <Trash2 size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
