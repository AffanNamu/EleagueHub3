import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { RolesPageClient } from '@/components/roles/RolesPageClient';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { listRoles } from '@/lib/repositories/adminRolesRepository';

export const dynamic = 'force-dynamic';

export default async function RolesPermissionsPage() {
  const identity = await getCurrentAdminIdentity();

  if (!identity?.isSuperAdmin) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">
          Roles & Permissions can only be managed by the Super Admin.
        </p>
      </div>
    );
  }

  const roles = await listRoles();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Roles & Permissions' }]} />
      <RolesPageClient initialRoles={roles} />
    </div>
  );
}
