'use client';

import Link from 'next/link';
import Image from 'next/image';
import { MessagesSquare, Trash2 } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { useDiscussionModerationAction } from '@/hooks/useDiscussionModerationAction';
import { formatRelativeTime } from '@/lib/utils';
import type { DiscussionThread } from '@/types/discussion';

export function DiscussionsTable({ threads, canModerate }: { threads: DiscussionThread[]; canModerate: boolean }) {
  const { removeThread, pendingId, error } = useDiscussionModerationAction();

  if (threads.length === 0) {
    return <EmptyState icon={MessagesSquare} title="No discussion threads found" />;
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
              <th className="px-4 py-3 font-medium">Thread</th>
              <th className="px-4 py-3 font-medium">Replies</th>
              <th className="px-4 py-3 font-medium">Last Activity</th>
              {canModerate && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {threads.map((thread) => (
              <tr key={thread.threadId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                <td className="px-4 py-3">
                  <Link href={`/content/discussions/${thread.threadId}`} className="flex items-start gap-3">
                    {thread.authorPhotoUrl ? (
                      <Image src={thread.authorPhotoUrl} alt={thread.authorDisplayName} width={28} height={28} className="rounded-full object-cover" />
                    ) : (
                      <div className="flex h-7 w-7 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                        {thread.authorDisplayName.slice(0, 2).toUpperCase()}
                      </div>
                    )}
                    <div className="min-w-0">
                      <p className="font-medium text-ink-primary">{thread.title}</p>
                      <p className="text-xs text-ink-secondary">by {thread.authorDisplayName || thread.authorId}</p>
                    </div>
                  </Link>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{thread.replyCount}</td>
                <td className="px-4 py-3 text-ink-secondary">
                  {thread.lastReplyAtMs ? formatRelativeTime(thread.lastReplyAtMs) : '—'}
                </td>
                {canModerate && (
                  <td className="px-4 py-3">
                    <button
                      onClick={() => removeThread(thread.threadId)}
                      disabled={pendingId === thread.threadId}
                      className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                      aria-label="Remove thread"
                    >
                      <Trash2 size={14} />
                    </button>
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
