// app/(admin)/layout.tsx
//
// Server Component gate for every route under (admin). Runs on the
// Node.js runtime (unlike middleware.ts, which only checks cookie
// presence at the Edge). This is where real authorization happens: the
// session cookie is cryptographically verified via the Admin SDK, and
// platform-admin status is re-checked against Firestore on every
// navigation — so revoking someone from app/admins.pricingAdmins[] takes
// effect immediately, not just at next login.

import { redirect } from 'next/navigation';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { AdminShell } from '@/components/layout/AdminShell';

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const identity = await getCurrentAdminIdentity();

  if (!identity || !identity.isPlatformAdmin) {
    redirect('/login');
  }

  return <AdminShell identity={identity}>{children}</AdminShell>;
}
