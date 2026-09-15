'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { Sidebar } from '@/components/layout/Sidebar';
import { TopBar } from '@/components/layout/TopBar';
import type { AdminIdentity } from '@/types/admin';

// Below md (768px) the sidebar is an off-canvas drawer, toggled from
// TopBar's hamburger button -- previously it was a fixed 240px column
// with no responsive handling at all, which on a phone-width viewport
// forced the whole layout wider than the screen (flex children don't
// shrink below their content's min-content size by default), pushing
// content off-screen and breaking nav button text out of its container.
export function AdminShell({
  identity,
  children,
}: {
  identity: AdminIdentity;
  children: React.ReactNode;
}) {
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const pathname = usePathname();

  // Close the drawer on every navigation rather than leaving it open
  // over the new page.
  useEffect(() => {
    setMobileNavOpen(false);
  }, [pathname]);

  return (
    <div className="flex h-screen overflow-hidden bg-base">
      <Sidebar identity={identity} mobileOpen={mobileNavOpen} onClose={() => setMobileNavOpen(false)} />
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <TopBar identity={identity} onMenuClick={() => setMobileNavOpen(true)} />
        <main className="flex-1 overflow-x-hidden overflow-y-auto p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}
