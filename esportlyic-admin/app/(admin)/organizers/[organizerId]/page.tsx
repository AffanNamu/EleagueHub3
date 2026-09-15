import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { OrganizerDetailPanel } from '@/components/organizers/OrganizerDetailPanel';
import { MasterLeagueStaffPanel } from '@/components/organizers/MasterLeagueStaffPanel';
import { getOrganizer } from '@/lib/repositories/organizersAdminRepository';
import {
  listMasterLeagueStaff,
  listMasterLeagueStaffAuditLog,
} from '@/lib/repositories/masterLeagueStaffAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function OrganizerDetailPage({ params }: { params: { organizerId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view organizers.</p>
      </div>
    );
  }

  const [organizer, staff, auditLog] = await Promise.all([
    getOrganizer(params.organizerId),
    listMasterLeagueStaff(params.organizerId),
    listMasterLeagueStaffAuditLog(params.organizerId),
  ]);
  if (!organizer) notFound();

  const canManageStaff = hasPermission(identity, 'organizers.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Organizers', href: '/organizers' }, { label: organizer.name || organizer.id }]} />
      <OrganizerDetailPanel organizer={organizer} canManage={canManageStaff} />
      <MasterLeagueStaffPanel
        organizerId={params.organizerId}
        staff={staff}
        auditLog={auditLog}
        canManage={canManageStaff}
      />
    </div>
  );
}
