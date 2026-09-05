'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { cn } from '@/lib/utils';
import type { GlobalChatRequestStatus } from '@/types/globalChatRequest';

const TABS: { label: string; value: GlobalChatRequestStatus | 'all' }[] = [
  { label: 'Pending', value: 'pending' },
  { label: 'Approved', value: 'approved' },
  { label: 'Rejected', value: 'rejected' },
  { label: 'All', value: 'all' },
];

export function GlobalChatRequestsFilterTabs() {
  const searchParams = useSearchParams();
  const activeStatus = searchParams.get('status') ?? 'pending';

  return (
    <div className="flex gap-1 border-b border-base-border">
      {TABS.map((tab) => {
        const isActive = activeStatus === tab.value;
        const href = tab.value === 'all' ? '/moderation/global-chat-requests' : `/moderation/global-chat-requests?status=${tab.value}`;
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
