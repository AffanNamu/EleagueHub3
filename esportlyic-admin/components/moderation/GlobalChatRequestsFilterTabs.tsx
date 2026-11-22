'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { cn } from '@/lib/utils';
import { DEFAULT_GLOBAL_CHAT_TAB, type GlobalChatRequestStatus } from '@/types/globalChatRequest';

const TABS: { label: string; value: GlobalChatRequestStatus | 'all' }[] = [
  { label: 'Members', value: 'approved' },
  { label: 'Removed', value: 'rejected' },
  { label: 'Pending (old requests)', value: 'pending' },
  { label: 'All', value: 'all' },
];

export function GlobalChatRequestsFilterTabs() {
  const searchParams = useSearchParams();
  const activeStatus = searchParams.get('status') ?? DEFAULT_GLOBAL_CHAT_TAB;

  return (
    <div className="flex gap-1 border-b border-base-border">
      {TABS.map((tab) => {
        const isActive = activeStatus === tab.value;
        // 'all' needs its own query value: with no ?status the page shows the default tab.
        const href = `/moderation/global-chat-requests?status=${tab.value}`;
        return (
          <Link
            key={tab.value}
            href={href}
            className={cn(
              'border-b-2 px-3 py-2 text-sm transition-colors',
              isActive ? 'border-brand text-brand' : 'border-transparent text-ink-secondary hover:text-ink-primary',
            )}
          >
            {tab.label}
          </Link>
        );
      })}
    </div>
  );
}
