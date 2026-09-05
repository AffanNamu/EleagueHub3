import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SearchBar } from '@/components/ui/SearchBar';
import { UsersTable } from '@/components/users/UsersTable';
import { listUsers } from '@/lib/repositories/usersAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function UsersPage({ searchParams }: { searchParams: { q?: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'users.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view users.</p>
      </div>
    );
  }

  const users = await listUsers({ search: searchParams.q });

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Users' }]} />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Users</h1>
          <p className="mt-1 text-sm text-ink-secondary">All player and team accounts on the platform.</p>
        </div>
        <SearchBar placeholder="Search by team name…" />
      </div>
      <UsersTable users={users} />
    </div>
  );
}
