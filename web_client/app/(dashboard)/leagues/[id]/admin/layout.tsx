'use client';

import { RoleGuard } from '@/components/guards/RoleGuard';
import { useParams } from 'next/navigation';

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const params = useParams();
  const leagueId = params.id as string;

  return (
    // Only 'owner' or 'admin' of this specific league can access the score editor
    <RoleGuard leagueId={leagueId} allowedRoles={['owner', 'admin']}>
      {children}
    </RoleGuard>
  );
}
