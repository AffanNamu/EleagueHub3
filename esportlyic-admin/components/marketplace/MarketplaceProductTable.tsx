'use client';

import Image from 'next/image';
import Link from 'next/link';
import { ShoppingBag, Pencil, Trash2, ExternalLink } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useMarketplaceListActions } from '@/hooks/useMarketplaceActions';
import { formatRelativeTime } from '@/lib/utils';
import type { MarketplaceProduct } from '@/types/marketplaceProduct';

export function MarketplaceProductTable({
  items,
  canManage,
}: {
  items: MarketplaceProduct[];
  canManage: boolean;
}) {
  const { remove, pendingId, error } = useMarketplaceListActions();

  if (items.length === 0) {
    return (
      <EmptyState
        icon={ShoppingBag}
        title="No marketplace listings yet"
        description="Create the first affiliate product listing for the Marketplace tab."
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
              <th className="px-4 py-3 font-medium">Product</th>
              <th className="px-4 py-3 font-medium">Category</th>
              <th className="px-4 py-3 font-medium">Price</th>
              <th className="px-4 py-3 font-medium">Seller</th>
              <th className="px-4 py-3 font-medium">Listed</th>
              {canManage && <th className="px-4 py-3 font-medium" />}
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        width={36}
                        height={36}
                        className="rounded-sm border border-base-border object-cover"
                      />
                    ) : (
                      <div className="flex h-9 w-9 items-center justify-center rounded-sm bg-base-raised text-ink-muted">
                        <ShoppingBag size={16} />
                      </div>
                    )}
                    <div>
                      <p className="font-medium text-ink-primary">{item.name}</p>
                      <a
                        href={item.affiliateUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="flex items-center gap-1 text-xs text-brand hover:underline"
                      >
                        Affiliate link <ExternalLink size={11} />
                      </a>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <Badge tone="info">{item.category || 'Uncategorized'}</Badge>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{item.price}</td>
                <td className="px-4 py-3 text-ink-secondary">{item.sellerName}</td>
                <td className="px-4 py-3 text-ink-secondary">{formatRelativeTime(item.createdAtMs)}</td>
                {canManage && (
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1">
                      <Link
                        href={`/marketplace/${item.id}`}
                        className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                        aria-label="Edit"
                      >
                        <Pencil size={14} />
                      </Link>
                      <button
                        onClick={() => remove(item.id, item.name)}
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
