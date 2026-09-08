'use client';

import { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { Users, BadgeCheck, Sparkles } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { Badge } from '@/components/ui/Badge';
import { formatRelativeTime } from '@/lib/utils';
import type { UserSummary } from '@/lib/repositories/usersAdminRepository';

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export function UsersTable({
  initialUsers,
  initialCursor,
  isSearch,
}: {
  initialUsers: UserSummary[];
  initialCursor: string | null;
  isSearch: boolean;
}) {
  const router = useRouter();
  const [users, setUsers] = useState(initialUsers);
  const [cursor, setCursor] = useState(initialCursor);
  const [loadingMore, setLoadingMore] = useState(false);

  async function loadMore() {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);

    const response = await fetch(`/api/admin/users?cursor=${encodeURIComponent(cursor)}`);
    const body = await response.json().catch(() => null);

    if (body?.users) {
      setUsers((prev) => [...prev, ...body.users]);
      setCursor(body.nextCursor ?? null);
    }
    setLoadingMore(false);
  }

  if (users.length === 0) {
    return <EmptyState icon={Users} title="No users found" description="Try a different search term." />;
  }

  return (
    <div className="space-y-3">
      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-base-border text-left text-xs text-ink-muted">
              <th className="px-4 py-3 font-medium">User</th>
              <th className="px-4 py-3 font-medium">Verified</th>
              <th className="px-4 py-3 font-medium">Joined</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => {
              const isNew = user.createdAtMs > 0 && Date.now() - user.createdAtMs < ONE_DAY_MS;
              return (
                <tr key={user.userId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                  <td className="px-4 py-3">
                    <Link href={`/users/${user.userId}`} className="flex items-center gap-3">
                      {user.photoUrl ? (
                        <Image
                          src={user.photoUrl}
                          alt={user.displayName}
                          width={32}
                          height={32}
                          className="rounded-full object-cover"
                        />
                      ) : (
                        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-base-raised text-xs text-ink-muted">
                          {user.displayName.slice(0, 2).toUpperCase()}
                        </div>
                      )}
                      <div>
                        <div className="flex items-center gap-1.5">
                          <p className="font-medium text-ink-primary">{user.displayName}</p>
                          {isNew && (
                            <Badge tone="success" className="inline-flex items-center gap-1">
                              <Sparkles size={10} /> New
                            </Badge>
                          )}
                        </div>
                        <p className="text-xs text-ink-muted">{user.userId}</p>
                      </div>
                    </Link>
                  </td>
                  <td className="px-4 py-3">
                    {user.isVerified && <BadgeCheck size={16} className="text-signal-success" />}
                  </td>
                  <td className="px-4 py-3 text-ink-secondary">
                    {user.createdAtMs ? formatRelativeTime(user.createdAtMs) : '—'}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {!isSearch && cursor && (
        <button
          onClick={loadMore}
          disabled={loadingMore}
          className="w-full rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-brand disabled:opacity-60"
        >
          {loadingMore ? 'Loading…' : 'Load More Users'}
        </button>
      )}
    </div>
  );
}
