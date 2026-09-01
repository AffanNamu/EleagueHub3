// app/(admin)/layout.tsx
//
// Server Component gate for every route under (admin). Runs on the
// Node.js runtime (unlike middleware.ts, which only checks cookie
// presence at the Edge). This is where real authorization happens:
// the session cookie is cryptographically verified via the Admin SDK,
// and platform-admin status is re-checked against Firestore on every
// navigation — so revoking someone from app/admins.pricingAdmins[]
// takes effect immediately, not just at next login.

import { redirect } from 'next/navigation';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const identity = await getCurrentAdminIdentity();

  if (!identity || !identity.isPlatformAdmin) {
    redirect('/login');
  }

  return (
    <div className="flex min-h-screen bg-base">
      {/* Sidebar and TopBar arrive in the next batch — this layout is
          intentionally minimal for now so the auth gate can be verified
          end-to-end before the full shell chrome is added around it. */}
      <div className="flex w-full flex-col">
        <header className="flex h-14 items-center justify-between border-b border-base-border px-6">
          <span className="font-display text-sm font-semibold text-ink-primary">
            Nomad Operations Center
          </span>
          <span className="text-xs text-ink-secondary">
            {identity.isSuperAdmin ? 'Super Admin' : 'Platform Admin'} · {identity.email ?? identity.uid}
          </span>
        </header>
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}
