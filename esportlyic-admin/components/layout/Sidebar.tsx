'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  BarChart3,
  Users,
  ShieldCheck,
  KeyRound,
  BadgeCheck,
  Trophy,
  Building2,
  FileText,
  MessagesSquare,
  FileWarning,
  MessageCircle,
  CreditCard,
  Tags,
  ScrollText,
  Settings,
  type LucideIcon,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { hasPermission } from '@/lib/auth/requirePermission';
import type { AdminIdentity } from '@/types/admin';

interface NavItem {
  label: string;
  href: string;
  icon: LucideIcon;
  permission?: string;
  superAdminOnly?: boolean;
}

interface NavSection {
  title: string;
  items: NavItem[];
}

const NAV_SECTIONS: NavSection[] = [
  {
    title: 'Overview',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Analytics', href: '/analytics', icon: BarChart3, permission: 'analytics.view' },
    ],
  },
  {
    title: 'User Management',
    items: [
      { label: 'Users', href: '/users', icon: Users, permission: 'users.view' },
      { label: 'Admins', href: '/admins', icon: ShieldCheck, superAdminOnly: true },
      { label: 'Roles & Permissions', href: '/roles-permissions', icon: KeyRound, superAdminOnly: true },
      { label: 'Verification', href: '/verification', icon: BadgeCheck, permission: 'verification.view' },
    ],
  },
  {
    title: 'Platform Management',
    items: [
      { label: 'Leagues', href: '/leagues', icon: Trophy, permission: 'leagues.view' },
      { label: 'Organizers', href: '/organizers', icon: Building2, permission: 'organizers.view' },
    ],
  },
  {
    title: 'Content & Engagement',
    items: [
      { label: 'Posts', href: '/content/posts', icon: FileText, permission: 'content.view' },
      { label: 'Discussions', href: '/content/discussions', icon: MessagesSquare, permission: 'content.view' },
    ],
  },
  {
    title: 'Moderation',
    items: [
      { label: 'Reports', href: '/moderation/reports', icon: FileWarning, permission: 'reports.view' },
      { label: 'Global Chat Requests', href: '/moderation/global-chat-requests', icon: MessageCircle, permission: 'global_chat_requests.view' },
    ],
  },
  {
    title: 'Monetization',
    items: [
      { label: 'Payments', href: '/payments', icon: CreditCard, permission: 'payments.view' },
      { label: 'Pricing', href: '/settings/pricing', icon: Tags, permission: 'pricing.view' },
    ],
  },
  {
    title: 'System',
    items: [
      { label: 'Audit Logs', href: '/audit-logs', icon: ScrollText, permission: 'audit_logs.view' },
      { label: 'Settings', href: '/settings', icon: Settings, permission: 'settings.manage' },
    ],
  },
];

function canSeeItem(item: NavItem, identity: AdminIdentity): boolean {
  if (item.superAdminOnly) return identity.isSuperAdmin;
  if (!item.permission) return true;
  return hasPermission(identity, item.permission);
}

export function Sidebar({ identity }: { identity: AdminIdentity }) {
  const pathname = usePathname();

  const visibleSections = NAV_SECTIONS.map((section) => ({
    ...section,
    items: section.items.filter((item) => canSeeItem(item, identity)),
  })).filter((section) => section.items.length > 0);

  return (
    <aside className="flex h-screen w-60 flex-shrink-0 flex-col border-r border-base-border bg-base-panel">
      <div className="flex h-14 items-center gap-2.5 border-b border-base-border px-4">
        <div className="flex h-7 w-7 items-center justify-center rounded-sm bg-brand text-xs font-semibold text-white">
          N
        </div>
        <div className="leading-tight">
          <p className="font-display text-sm font-semibold text-ink-primary">Nomad Ops</p>
          <p className="text-[11px] text-ink-muted">eSports Platform</p>
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        {visibleSections.map((section) => (
          <div key={section.title} className="mb-5">
            <p className="mb-1.5 px-2 text-[11px] font-medium text-ink-muted">{section.title}</p>
            <ul className="space-y-0.5">
              {section.items.map((item) => {
                const isActive = pathname === item.href || pathname.startsWith(`${item.href}/`);
                const Icon = item.icon;
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      className={cn(
                        'flex items-center gap-2.5 rounded-sm px-2.5 py-1.5 text-sm transition-colors',
                        isActive
                          ? 'bg-brand-faint text-brand'
                          : 'text-ink-secondary hover:bg-base-raised hover:text-ink-primary',
                      )}
                    >
                      <Icon size={16} strokeWidth={2} />
                      {item.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}

        {!identity.isSuperAdmin && !identity.isLegacyFullAccess && (
          <div className="mt-2 rounded-sm bg-base-raised px-3 py-2.5">
            <p className="text-xs text-ink-muted">Signed in as</p>
            <p className="text-xs font-medium text-ink-primary">
              {identity.roleNames.join(', ') || 'No roles assigned'}
            </p>
          </div>
        )}
      </nav>
    </aside>
  );
}
