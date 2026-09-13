'use client';

import Link from 'next/link';
import { Sparkles, Pencil, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useHomeContentListActions } from '@/hooks/useHomeContentActions';
import { formatRelativeTime } from '@/lib/utils';
import type { HomeContentItem } from '@/types/homeContent';

const TYPE_LABEL: Record<HomeContentItem['type'], string> = {
  hero: 'Hero banner',
  promo_card: 'Promo card',
  announcement: 'Announcement',
};

function scheduleLabel(item: HomeContentItem): string {
  if (!item.startAtMs && !item.endAtMs) return 'Always';
  const start = item.startAtMs ? new Date(item.startAtMs).toLocaleDateString() : '…';
  const end = item.endAtMs ? new Date(item.endAtMs).toLocaleDateString() : '…';
  return `${start} – ${end}`;
}

export function HomeContentTable({ items, canManage }: { items: HomeContentItem[]; canManage: boolean }) {
  const { toggleActive, remove, pendingId, error } = useHomeContentListActions();

  if (items.length === 0) {
    return (
      <EmptyState
        icon={Sparkles}
        title="No home content yet"
        description="Create a hero banner, promo card, or announcement for the app/web home screen."
      />
    );
  }

  return (
    <div className="space-y-3">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-base-border text-left text-xs text-ink-muted">
              <th className="px-4 py-3 font-medium">Title</th>
              <th className="px-4 py-3 font-medium">Type</th>
              <th className="px-4 py-3 font-medium">Order</th>
              <th className="px-4 py-3 font-medium">Schedule</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Updated</th>
              {canManage && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                <td className="px-4 py-3">
                  <p className="font-medium text-ink-primary">{item.title}</p>
                  {item.subtitle && <p className="line-clamp-1 text-xs text-ink-secondary">{item.subtitle}</p>}
                </td>
                <td className="px-4 py-3">
                  <Badge tone="info">{TYPE_LABEL[item.type]}</Badge>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{item.order}</td>
                <td className="px-4 py-3 text-ink-secondary">{scheduleLabel(item)}</td>
                <td className="px-4 py-3">
                  {canManage ? (
                    <button
                      onClick={() => toggleActive(item.id, !item.active)}
                      disabled={pendingId === item.id}
                      className="disabled:opacity-60"
                    >
                      <Badge tone={item.active ? 'success' : 'neutral'}>{item.active ? 'Active' : 'Inactive'}</Badge>
                    </button>
                  ) : (
                    <Badge tone={item.active ? 'success' : 'neutral'}>{item.active ? 'Active' : 'Inactive'}</Badge>
                  )}
                </td>
                <td className="px-4 py-3 text-ink-secondary">{formatRelativeTime(item.updatedAtMs)}</td>
                {canManage && (
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1">
                      <Link
                        href={`/content/home/${item.id}`}
                        className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                        aria-label="Edit"
                      >
                        <Pencil size={14} />
                      </Link>
                      <button
                        onClick={() => remove(item.id)}
                        disabled={pendingId === item.id}
                        className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                        aria-label="Delete"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
