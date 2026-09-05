import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { PostDetailPanel } from '@/components/moderation/PostDetailPanel';
import { getPost, listComments } from '@/lib/repositories/contentAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function PostDetailPage({ params }: { params: { postId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view content.</p>
      </div>
    );
  }

  const post = await getPost(params.postId);
  if (!post) notFound();

  const comments = await listComments(params.postId);
  const canModerate = hasPermission(identity, 'content.moderate');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Posts', href: '/content/posts' }, { label: post.postId }]} />
      <PostDetailPanel post={post} comments={comments} canModerate={canModerate} />
    </div>
  );
}
