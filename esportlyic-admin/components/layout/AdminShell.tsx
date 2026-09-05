import { Sidebar } from '@/components/layout/Sidebar';
import { TopBar } from '@/components/layout/TopBar';
import type { AdminIdentity } from '@/types/admin';

export function AdminShell({
  identity,
  children,
}: {
  identity: AdminIdentity;
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-screen overflow-hidden bg-base">
      <Sidebar identity={identity} />
      <div className="flex flex-1 flex-col overflow-hidden">
        <TopBar identity={identity} />
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
