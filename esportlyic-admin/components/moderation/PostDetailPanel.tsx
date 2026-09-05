'use client';

import Image from 'next/image';
import { Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { CommentsList } from '@/components/moderation/CommentsList';
import { useContentModerationAction } from '@/hooks/useContentModerationAction';
import { postTypeLabel } from '@/lib/models/content';
import { formatRelativeTime } from '@/lib/utils';
import type { PostComment, PublicPost } from '@/types/content';

export function PostDetailPanel({
  post,
  comments,
  canModerate,
}: {
  post: PublicPost;
  comments: PostComment[];
  canModerate: boolean;
}) {
  const { removePost, pendingId, error } = useContentModerationAction();

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
            {post.authorPhotoUrl ? (
              <Image src={post.authorPhotoUrl} alt={post.authorDisplayName} width={40} height={40} className="rounded-full object-cover" />
            ) : (
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                {post.authorDisplayName.slice(0, 2).toUpperCase()}
              </div>
            )}
            <div>
              <p className="text-sm font-medium text-ink-primary">{post.authorDisplayName || post.authorId}</p>
              <p className="text-xs text-ink-muted">{formatRelativeTime(post.createdAtMs)}</p>
            </div>
          </div>
          <Badge tone="info">{postTypeLabel(post.postType)}</Badge>
        </div>

        {post.text && <p className="mt-4 text-sm text-ink-primary">{post.text}</p>}

        {post.postType === 'match_result' && (
          <div className="mt-3 rounded-sm bg-base-raised p-3 text-center">
            <p className="text-xs text-ink-muted">vs {post.matchOpponentName || 'Unknown opponent'}</p>
            <p className="mt-1 font-display text-xl font-semibold text-ink-primary">
              {post.matchScoreHome} — {post.matchScoreAway}
            </p>
          </div>
        )}

        {post.mediaUrl && (
          <div className="mt-3 overflow-hidden rounded-sm border border-base-border">
            <Image src={post.mediaUrl} alt="Post media" width={600} height={400} className="w-full object-cover" />
          </div>
        )}

        {post.leagueName && (
          <p className="mt-3 text-xs text-ink-muted">Linked league: {post.leagueName}</p>
        )}

        <div className="mt-4 flex items-center justify-between border-t border-base-border pt-3">
          <p className="text-xs text-ink-secondary">
            {post.likeCount} likes · {post.commentCount} comments
          </p>
          {canModerate && (
            <button
              onClick={() => removePost(post.postId)}
              disabled={pendingId === post.postId}
              className="flex items-center gap-1.5 rounded-sm border border-base-border bg-base-raised px-3 py-1.5 text-xs font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger disabled:opacity-60"
            >
              <Trash2 size={13} /> Remove Post
            </button>
          )}
        </div>
      </div>

      <div className="panel p-5">
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">
          Comments ({comments.length})
        </h2>
        <CommentsList postId={post.postId} comments={comments} canModerate={canModerate} />
      </div>
    </div>
  );
}
