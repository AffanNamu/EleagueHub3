'use client';

import Image from 'next/image';
import { Trash2 } from 'lucide-react';
import { useContentModerationAction } from '@/hooks/useContentModerationAction';
import { formatRelativeTime } from '@/lib/utils';
import type { PostComment } from '@/types/content';

export function CommentsList({
  postId,
  comments,
  canModerate,
}: {
  postId: string;
  comments: PostComment[];
  canModerate: boolean;
}) {
  const { removeComment, pendingId, error } = useContentModerationAction();

  if (comments.length === 0) {
    return <p className="text-sm text-ink-secondary">No comments on this post.</p>;
  }

  return (
    <div className="space-y-3">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      {comments.map((comment) => (
        <div key={comment.commentId} className="flex items-start gap-3 rounded-sm bg-base-raised p-3">
          {comment.authorPhotoUrl ? (
            <Image src={comment.authorPhotoUrl} alt={comment.authorDisplayName} width={28} height={28} className="rounded-full object-cover" />
          ) : (
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-base text-xs text-ink-muted">
              {comment.authorDisplayName.slice(0, 2).toUpperCase()}
            </div>
          )}
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium text-ink-primary">{comment.authorDisplayName || comment.authorId}</p>
            <p className="mt-0.5 text-sm text-ink-secondary">{comment.text}</p>
            <p className="mt-1 text-xs text-ink-muted">{formatRelativeTime(comment.createdAtMs)}</p>
          </div>
          {canModerate && (
            <button
              onClick={() => removeComment(postId, comment.commentId)}
              disabled={pendingId === comment.commentId}
              className="flex-shrink-0 rounded-sm p-1.5 text-ink-secondary hover:bg-base hover:text-signal-danger disabled:opacity-60"
              aria-label="Remove comment"
            >
              <Trash2 size={14} />
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
