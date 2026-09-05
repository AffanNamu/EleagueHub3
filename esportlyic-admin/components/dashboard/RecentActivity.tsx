import Link from 'next/link';
import { FileWarning, ShieldQuestion, MessageCircle } from 'lucide-react';
import type { RecentEvent } from '@/lib/repositories/dashboardRepository';
import { formatRelativeTime } from '@/lib/utils';

const HREF_BY_KIND: Record<RecentEvent['kind'], string> = {
  verification_request: '/verification',
  report: '/moderation/reports',
  global_chat_request: '/moderation/global-chat-requests',
};

const ICON_BY_KIND: Record<RecentEvent['kind'], typeof FileWarning> = {
  verification_request: ShieldQuestion,
  report: FileWarning,
  global_chat_request: MessageCircle,
};

export function RecentActivity({ events }: { events: RecentEvent[] }) {
  return (
    <div className="panel p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Recent Platform Events</h2>
        <Link href="/audit-logs" className="text-xs text-brand hover:underline">
          View all
        </Link>
      </div>

      {events.length === 0 ? (
        <p className="text-sm text-ink-secondary">No recent activity.</p>
      ) : (
        <ul className="space-y-3">
          {events.map((event) => {
            const Icon = ICON_BY_KIND[event.kind];
            return (
              <li key={`${event.kind}-${event.id}`}>
                <Link
                  href={HREF_BY_KIND[event.kind]}
                  className="flex items-start gap-3 rounded-sm px-1.5 py-1 transition-colors hover:bg-base-raised"
                >
                  <div className="mt-0.5 flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-sm bg-base-raised text-ink-secondary">
                    <Icon size={14} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-ink-primary">{event.title}</p>
                    <p className="text-xs text-ink-secondary">{event.detail}</p>
                  </div>
                  <span className="flex-shrink-0 text-xs text-ink-muted">
                    {event.timestampMs ? formatRelativeTime(event.timestampMs) : '—'}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
