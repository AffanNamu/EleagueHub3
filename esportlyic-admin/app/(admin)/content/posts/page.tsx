import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { PostsTable } from '@/components/moderation/PostsTable';
import { listPosts } from '@/lib/repositories/contentAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function PostsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view content.</p>
      </div>
    );
  }

  const posts = await listPosts();
  const canModerate = hasPermission(identity, 'content.moderate');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Posts' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Public Feed Posts</h1>
        <p className="mt-1 text-sm text-ink-secondary">Most recent posts across the platform.</p>
      </div>
      <PostsTable posts={posts} canModerate={canModerate} />
    </div>
  );
}
