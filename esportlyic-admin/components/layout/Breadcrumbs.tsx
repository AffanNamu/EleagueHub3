import Link from 'next/link';
import { ChevronRight } from 'lucide-react';

export interface Crumb {
  label: string;
  href?: string;
}

export function Breadcrumbs({ items }: { items: Crumb[] }) {
  return (
    <nav className="mb-4 flex items-center gap-1.5 text-sm text-ink-secondary">
      {items.map((item, index) => {
        const isLast = index === items.length - 1;
        return (
          <span key={`${item.label}-${index}`} className="flex items-center gap-1.5">
            {item.href && !isLast ? (
              <Link href={item.href} className="hover:text-ink-primary">
                {item.label}
              </Link>
            ) : (
              <span className={isLast ? 'text-ink-primary' : undefined}>{item.label}</span>
            )}
            {!isLast && <ChevronRight size={13} className="text-ink-muted" />}
          </span>
        );
      })}
    </nav>
  );
}
