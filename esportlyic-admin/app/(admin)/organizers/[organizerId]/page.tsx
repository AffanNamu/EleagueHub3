import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { OrganizerDetailPanel } from '@/components/organizers/OrganizerDetailPanel';
import { getOrganizer } from '@/lib/repositories/organizersAdminRepository';
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

  const organizer = await getOrganizer(params.organizerId);
  if (!organizer) notFound();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Organizers', href: '/organizers' }, { label: organizer.name || organizer.id }]} />
      <OrganizerDetailPanel organizer={organizer} />
    </div>
  );
}
