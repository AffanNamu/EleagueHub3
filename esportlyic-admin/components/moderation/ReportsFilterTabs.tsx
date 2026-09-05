'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { cn } from '@/lib/utils';
import type { ReportStatus } from '@/types/report';

const TABS: { label: string; value: ReportStatus | 'all' }[] = [
  { label: 'Pending', value: 'pending' },
  { label: 'Reviewed', value: 'reviewed' },
  { label: 'Dismissed', value: 'dismissed' },
  { label: 'All', value: 'all' },
];

export function ReportsFilterTabs() {
  const searchParams = useSearchParams();
  const activeStatus = searchParams.get('status') ?? 'pending';

  return (
    <div className="flex gap-1 border-b border-base-border">
      {TABS.map((tab) => {
        const isActive = activeStatus === tab.value;
        const href = tab.value === 'all' ? '/moderation/reports' : `/moderation/reports?status=${tab.value}`;
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
