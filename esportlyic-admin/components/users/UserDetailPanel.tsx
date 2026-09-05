import Image from 'next/image';
import { Users as UsersIcon, BadgeCheck } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { UserPlanBadge } from '@/components/users/UserPlanBadge';
import { UserModerationPanel } from '@/components/users/UserModerationPanel';
import { EntitlementOverridePanel } from '@/components/users/EntitlementOverridePanel';
import { UserPaymentHistory } from '@/components/users/UserPaymentHistory';
import { formatRelativeTime, formatNumber } from '@/lib/utils';
import { isBadgeCurrentlyActive } from '@/lib/models/userProfile';
import type { AdminUserProfile } from '@/types/user';
import type { Payment } from '@/types/payment';

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="panel p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-lg font-semibold text-ink-primary">{value}</p>
    </div>
  );
}

export function UserDetailPanel({
  profile,
  payments,
  canModerate,
  canOverrideEntitlement,
  canViewPayments,
}: {
  profile: AdminUserProfile;
  payments: Payment[];
  canModerate: boolean;
  canOverrideEntitlement: boolean;
  canViewPayments: boolean;
}) {
  const photo = profile.profileImageUrl || profile.teamImageUrl || profile.photoUrl;

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <div className="space-y-4 lg:col-span-2">
        <div className="panel p-5">
          <div className="flex items-start gap-4">
            {photo ? (
              <Image src={photo} alt={profile.teamName} width={56} height={56} className="rounded-md object-cover" />
            ) : (
              <div className="flex h-14 w-14 items-center justify-center rounded-md bg-base-raised text-ink-muted">
                <UsersIcon size={22} />
              </div>
            )}
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <h1 className="font-display text-lg font-semibold text-ink-primary">{profile.teamName || 'User'}</h1>
                {profile.isVerified && <BadgeCheck size={17} className="text-signal-success" />}
                <UserPlanBadge profile={profile} />
              </div>
              {profile.usernameLower && <p className="mt-0.5 text-sm text-ink-secondary">@{profile.usernameLower}</p>}
              <p className="mt-2 text-xs text-ink-muted">
                {profile.userId} · Joined {profile.createdAtMs ? formatRelativeTime(profile.createdAtMs) : '—'}
              </p>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Followers" value={formatNumber(profile.followersCount)} />
          <Stat label="Following" value={formatNumber(profile.followingCount)} />
          <Stat label="Auth Provider" value={profile.authProvider || '—'} />
          <Stat label="Share ID" value={profile.shareId || '—'} />
        </div>

        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Verification Badges</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            {[
              { label: 'Green (Verified)', active: profile.badges.greenVerified, expiresAtMs: profile.badges.greenExpiresAtMs, source: profile.badges.greenSource },
              { label: 'Organizer (Gold)', active: profile.badges.organizerVerified, expiresAtMs: profile.badges.organizerExpiresAtMs, source: profile.badges.organizerSource },
              { label: 'Staff', active: profile.badges.staffVerified, expiresAtMs: profile.badges.staffExpiresAtMs, source: profile.badges.staffSource },
            ].map((badge) => {
              const currentlyActive = badge.active && isBadgeCurrentlyActive(badge.expiresAtMs);
              return (
                <div key={badge.label} className="rounded-sm bg-base-raised p-3">
                  <p className="text-sm text-ink-primary">{badge.label}</p>
                  <Badge tone={currentlyActive ? 'success' : 'neutral'} className="mt-1.5">
                    {currentlyActive ? 'Active' : 'Not Active'}
                  </Badge>
                  {badge.source && <p className="mt-1.5 text-xs text-ink-muted">Source: {badge.source}</p>}
                </div>
              );
            })}
          </div>
        </div>

        {profile.plan.activePlanId && (
          <div className="panel p-5">
            <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Plan Subscription</h2>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <div>
                <p className="text-xs text-ink-muted">Provider</p>
                <p className="mt-0.5 text-sm text-ink-primary">{profile.plan.planProvider || '—'}</p>
              </div>
              <div>
                <p className="text-xs text-ink-muted">Duration</p>
                <p className="mt-0.5 text-sm text-ink-primary">{profile.plan.activePlanDurationId || '—'}</p>
              </div>
              <div>
                <p className="text-xs text-ink-muted">Expires</p>
                <p className="mt-0.5 text-sm text-ink-primary">
                  {profile.plan.planExpiresAtMs ? formatRelativeTime(profile.plan.planExpiresAtMs) : '—'}
                </p>
              </div>
              <div>
                <p className="text-xs text-ink-muted">Receipt</p>
                <p className="mt-0.5 truncate text-sm text-ink-primary">{profile.plan.planReceiptId || '—'}</p>
              </div>
            </div>
          </div>
        )}

        {canViewPayments && <UserPaymentHistory payments={payments} />}
      </div>

      <div className="space-y-4">
        {canModerate && <UserModerationPanel profile={profile} />}
        {canOverrideEntitlement && <EntitlementOverridePanel profile={profile} />}
      </div>
    </div>
  );
}
