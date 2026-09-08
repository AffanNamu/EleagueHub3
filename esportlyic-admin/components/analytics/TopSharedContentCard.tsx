import { TrendingUp } from 'lucide-react';
import { formatNumber } from '@/lib/utils';
import type { LinkRollup } from '@/types/linkAnalytics';

const ENTITY_TYPE_LABEL: Record<string, string> = {
  userProfile: 'User Profile',
  competition: 'Competition',
  team: 'Team',
  post: 'Post',
  organizerWorkspace: 'Organizer',
  marketProduct: 'Marketplace Item',
  tournament: 'Tournament',
  news: 'News',
  achievement: 'Achievement',
};

export function TopSharedContentCard({
  title,
  rollups,
  metric,
}: {
  title: string;
  rollups: LinkRollup[];
  metric: 'shareCount' | 'clickCount';
}) {
  return (
    <div className="panel p-5">
      <div className="mb-4 flex items-center gap-2">
        <TrendingUp size={16} className="text-ink-secondary" />
        <h2 className="font-display text-sm font-semibold text-ink-primary">{title}</h2>
      </div>

      {rollups.length === 0 ? (
        <p className="text-sm text-ink-secondary">No activity recorded yet.</p>
      ) : (
        <div className="space-y-2">
          {rollups.map((rollup) => (
            <div key={rollup.rollupId} className="flex items-center justify-between rounded-sm bg-base-raised px-3 py-2">
              <div className="min-w-0">
                <p className="truncate text-sm text-ink-primary">
                  {rollup.entityName ?? `${ENTITY_TYPE_LABEL[rollup.entityType] ?? rollup.entityType} · ${rollup.entityId}`}
                </p>
                <p className="text-xs text-ink-muted">{ENTITY_TYPE_LABEL[rollup.entityType] ?? rollup.entityType}</p>
              </div>
              <p className="flex-shrink-0 text-sm font-medium text-ink-primary">
                {formatNumber(rollup[metric])}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
