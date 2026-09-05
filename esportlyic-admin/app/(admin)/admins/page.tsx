import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { AdminsPageClient } from '@/components/admins/AdminsPageClient';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { listAdminUsers } from '@/lib/repositories/adminUsersRepository';
import { listRoles } from '@/lib/repositories/adminRolesRepository';

export const dynamic = 'force-dynamic';

export default async function AdminsPage() {
  const identity = await getCurrentAdminIdentity();

  if (!identity?.isSuperAdmin) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">Admin management can only be performed by the Super Admin.</p>
      </div>
    );
  }

  const [admins, roles] = await Promise.all([listAdminUsers(), listRoles()]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Admins' }]} />
      <AdminsPageClient initialAdmins={admins} roles={roles} />
    </div>
  );
}
