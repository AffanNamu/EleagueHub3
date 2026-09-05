'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Search, LogOut, ChevronDown } from 'lucide-react';
import type { AdminIdentity } from '@/types/admin';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';

export function TopBar({ identity }: { identity: AdminIdentity }) {
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);

  async function handleSignOut() {
    if (signingOut) return;
    setSigningOut(true);
    try {
      await fetch('/api/admin/auth/session', { method: 'DELETE' });
      await signOut(auth);
    } finally {
      router.replace('/login');
      router.refresh();
    }
  }

  const initials = (identity.email ?? identity.uid).slice(0, 2).toUpperCase();

  return (
    <header className="flex h-14 flex-shrink-0 items-center justify-between border-b border-base-border bg-base px-6">
      <div className="flex max-w-md flex-1 items-center gap-2 rounded-sm border border-base-border bg-base-raised px-3 py-1.5">
        <Search size={15} className="text-ink-muted" />
        <input
          type="text"
          placeholder="Search users, leagues, organizers…"
          className="w-full bg-transparent text-sm text-ink-primary placeholder:text-ink-muted focus:outline-none"
        />
      </div>

      <div className="flex items-center gap-4">
        <div className="group relative">
          <button className="flex items-center gap-2 rounded-sm px-2 py-1.5 text-sm text-ink-primary hover:bg-base-raised">
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-brand-faint text-xs font-semibold text-brand">
              {initials}
            </div>
            <div className="text-left leading-tight">
              <p className="text-xs font-medium">{identity.isSuperAdmin ? 'Super Admin' : 'Platform Admin'}</p>
              <p className="max-w-[140px] truncate text-[11px] text-ink-muted">
                {identity.email ?? identity.uid}
              </p>
            </div>
            <ChevronDown size={14} className="text-ink-muted" />
          </button>

          <div className="invisible absolute right-0 top-full z-20 mt-1 w-44 rounded-md border border-base-border bg-base-panel py-1 opacity-0 shadow-lg transition-opacity group-hover:visible group-hover:opacity-100">
            <button
              onClick={handleSignOut}
              disabled={signingOut}
              className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
            >
              <LogOut size={14} />
              {signingOut ? 'Signing out…' : 'Sign out'}
            </button>
          </div>
        </div>
      </div>
    </header>
  );
}
