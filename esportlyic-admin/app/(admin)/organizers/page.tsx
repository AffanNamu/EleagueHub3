import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SearchBar } from '@/components/ui/SearchBar';
import { OrganizersTable } from '@/components/organizers/OrganizersTable';
import { listOrganizers } from '@/lib/repositories/organizersAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function OrganizersPage({ searchParams }: { searchParams: { q?: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view organizers.</p>
      </div>
    );
  }

  const organizers = await listOrganizers({ search: searchParams.q });

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Organizers' }]} />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Organizer Workspaces</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Master League workspaces across the platform.
          </p>
        </div>
        <SearchBar placeholder="Search by name…" />
      </div>
      <OrganizersTable organizers={organizers} />
    </div>
  );
}
