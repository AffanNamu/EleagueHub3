import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { FootballNewsApiKeyForm } from '@/components/settings/FootballNewsApiKeyForm';
import {
  getFootballNewsMetrics,
  getFootballNewsApiKeyStatus,
} from '@/lib/repositories/footballNewsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

function StatTile({ label, value }: { label: string; value: number }) {
  return (
    <div className="panel p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-lg font-semibold text-ink-primary">{value}</p>
    </div>
  );
}

export default async function FootballNewsSettingsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view this page.</p>
      </div>
    );
  }

  const [metrics, apiKeyStatus] = await Promise.all([
    getFootballNewsMetrics(),
    getFootballNewsApiKeyStatus(),
  ]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings', href: '/settings' }, { label: 'Football News' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Football News</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          GNews usage for {metrics.date} (UTC) powering the News tab inside Football Hub. A
          separate provider and quota from API-Football -- everything here is read directly from
          Firestore on every page load, there's no separate analytics pipeline behind it.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <StatTile label="API requests today" value={metrics.apiRequests} />
        <StatTile label="Cache hits today" value={metrics.cacheHits} />
        <StatTile label="Provider errors today" value={metrics.providerErrors} />
      </div>
      <p className="text-xs text-ink-muted">
        Free GNews plan cap is 100 requests/day. "API requests" above is every call that actually
        reached gnews.io (a cache hit, shared across every user who opens the News tab within the
        same 30-minute window, costs nothing).
      </p>

      <FootballNewsApiKeyForm
        configured={apiKeyStatus.configured}
        maskedKey={apiKeyStatus.maskedKey}
        keyUpdatedAtMs={apiKeyStatus.keyUpdatedAtMs}
        keyUpdatedByEmail={apiKeyStatus.keyUpdatedByEmail}
      />
    </div>
  );
}
