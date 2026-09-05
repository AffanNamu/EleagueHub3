'use client';

import Link from 'next/link';
import Image from 'next/image';
import { FileText, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useContentModerationAction } from '@/hooks/useContentModerationAction';
import { postTypeLabel } from '@/lib/models/content';
import { formatRelativeTime } from '@/lib/utils';
import type { PublicPost } from '@/types/content';

export function PostsTable({ posts, canModerate }: { posts: PublicPost[]; canModerate: boolean }) {
  const { removePost, pendingId, error } = useContentModerationAction();

  if (posts.length === 0) {
    return <EmptyState icon={FileText} title="No posts found" />;
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
              <th className="px-4 py-3 font-medium">Post</th>
              <th className="px-4 py-3 font-medium">Type</th>
              <th className="px-4 py-3 font-medium">Engagement</th>
              <th className="px-4 py-3 font-medium">Posted</th>
              {canModerate && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {posts.map((post) => (
              <tr key={post.postId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                <td className="px-4 py-3">
                  <Link href={`/content/posts/${post.postId}`} className="flex items-start gap-3">
                    {post.authorPhotoUrl ? (
                      <Image src={post.authorPhotoUrl} alt={post.authorDisplayName} width={28} height={28} className="rounded-full object-cover" />
                    ) : (
                      <div className="flex h-7 w-7 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                        {post.authorDisplayName.slice(0, 2).toUpperCase()}
                      </div>
                    )}
                    <div className="min-w-0">
                      <p className="font-medium text-ink-primary">{post.authorDisplayName || post.authorId}</p>
                      <p className="line-clamp-1 text-xs text-ink-secondary">{post.text || '(media post, no caption)'}</p>
                    </div>
                  </Link>
                </td>
                <td className="px-4 py-3">
                  <Badge tone="info">{postTypeLabel(post.postType)}</Badge>
                  {post.isPromoted && <Badge tone="brand" className="ml-1.5">Promoted</Badge>}
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {post.likeCount} likes · {post.commentCount} comments
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {post.createdAtMs ? formatRelativeTime(post.createdAtMs) : '—'}
                </td>
                {canModerate && (
                  <td className="px-4 py-3">
                    <button
                      onClick={() => removePost(post.postId)}
                      disabled={pendingId === post.postId}
                      className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                      aria-label="Remove post"
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
