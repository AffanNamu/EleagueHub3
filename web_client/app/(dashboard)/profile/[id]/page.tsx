'use client';

import { useParams } from 'next/navigation';
import { ProfileDetailView } from '@/components/profile/ProfileDetailView';

export default function ProfileScreen() {
  const params = useParams();
  const routeId = (params.id as string) || '';
  return <ProfileDetailView routeUid={routeId} />;
}
