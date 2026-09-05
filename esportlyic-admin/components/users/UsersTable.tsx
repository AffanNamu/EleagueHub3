import Link from 'next/link';
import Image from 'next/image';
import { Users, BadgeCheck } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import type { UserSummary } from '@/lib/repositories/usersAdminRepository';

export function UsersTable({ users }: { users: UserSummary[] }) {
  if (users.length === 0) {
    return <EmptyState icon={Users} title="No users found" description="Try a different search term." />;
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">User</th>
            <th className="px-4 py-3 font-medium">Verified</th>
          </tr>
        </thead>
        <tbody>
          {users.map((user) => (
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
                    <p className="font-medium text-ink-primary">{user.displayName}</p>
                    <p className="text-xs text-ink-muted">{user.userId}</p>
                  </div>
                </Link>
              </td>
              <td className="px-4 py-3">
                {user.isVerified && <BadgeCheck size={16} className="text-signal-success" />}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
