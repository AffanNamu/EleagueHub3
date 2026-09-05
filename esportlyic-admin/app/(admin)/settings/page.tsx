import Link from 'next/link';
import { Tags, Activity } from 'lucide-react';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function SettingsHubPage() {
  const identity = await getCurrentAdminIdentity();

  const links = [
    {
      href: '/settings/pricing',
      icon: Tags,
      title: 'Pricing',
      description: 'Plan fees, verification fees, and payment provider toggles.',
      visible: hasPermission(identity, 'pricing.view'),
    },
    {
      href: '/settings/system-health',
      icon: Activity,
      title: 'System Health',
      description: 'Not built yet — no automated health pipeline exists to surface here.',
      visible: hasPermission(identity, 'settings.manage'),
      disabled: true,
    },
  ].filter((link) => link.visible);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings' }]} />
      <h1 className="font-display text-xl font-semibold text-ink-primary">Settings</h1>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {links.map((link) => {
          const Icon = link.icon;
          const content = (
            <div className="panel flex items-start gap-3 p-4 transition-colors hover:border-brand/40">
              <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-brand-faint text-brand">
                <Icon size={17} />
              </div>
              <div>
                <p className="text-sm font-medium text-ink-primary">{link.title}</p>
                <p className="mt-0.5 text-xs text-ink-secondary">{link.description}</p>
              </div>
            </div>
          );

          return link.disabled ? (
            <div key={link.href} className="opacity-60">
              {content}
            </div>
          ) : (
            <Link key={link.href} href={link.href}>
              {content}
            </Link>
          );
        })}
      </div>
    </div>
  );
}
