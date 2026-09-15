import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { OrganizerEditForm } from '@/components/organizers/OrganizerEditForm';
import { getOrganizer } from '@/lib/repositories/organizersAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function EditOrganizerPage({ params }: { params: { organizerId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage organizers.</p>
      </div>
    );
  }

  const organizer = await getOrganizer(params.organizerId);
  if (!organizer) notFound();

  return (
    <div className="space-y-4">
      <Breadcrumbs
        items={[
          { label: 'Organizers', href: '/organizers' },
          { label: organizer.name || organizer.id, href: `/organizers/${organizer.id}` },
          { label: 'Edit' },
        ]}
      />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Edit Organizer Workspace</h1>
      </div>
      <OrganizerEditForm organizer={organizer} />
    </div>
  );
}
