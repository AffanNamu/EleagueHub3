import { Badge } from '@/components/ui/Badge';
import { planLabel, isPlanCurrentlyActive } from '@/lib/models/userProfile';
import type { AdminUserProfile } from '@/types/user';

const PLAN_TONE: Record<string, 'neutral' | 'brand' | 'success'> = {
  basic: 'neutral',
  pro: 'brand',
  elite: 'success',
};

export function UserPlanBadge({ profile }: { profile: AdminUserProfile }) {
  const active = isPlanCurrentlyActive(profile);
  const planId = profile.plan.activePlanId || 'basic';

  return (
    <Badge tone={active ? PLAN_TONE[planId] ?? 'neutral' : 'neutral'}>
      {planLabel(planId)}
      {!active && planId !== 'basic' && planId !== '' ? ' (Expired)' : ''}
    </Badge>
  );
}
