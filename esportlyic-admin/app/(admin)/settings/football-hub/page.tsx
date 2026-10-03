import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { FootballHubPollerToggle } from '@/components/settings/FootballHubPollerToggle';
import { FootballHubApiKeyForm } from '@/components/settings/FootballHubApiKeyForm';
import {
  getFootballHubMetrics,
  getFootballHubConfig,
  getFootballHubApiKeyStatus,
} from '@/lib/repositories/footballHubAdminRepository';
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

export default async function FootballHubSettingsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view this page.</p>
      </div>
    );
  }

  const [metrics, config, apiKeyStatus] = await Promise.all([
    getFootballHubMetrics(),
    getFootballHubConfig(),
    getFootballHubApiKeyStatus(),
  ]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings', href: '/settings' }, { label: 'Football Hub' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Football Hub</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          API-Football usage for {metrics.date} (UTC) and the live-score poller that drives goal
          notifications. Everything here is read directly from Firestore on every page load --
          there's no separate analytics pipeline behind it.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <StatTile label="API requests today" value={metrics.apiRequests} />
        <StatTile label="Cache hits today" value={metrics.cacheHits} />
        <StatTile label="Provider errors today" value={metrics.providerErrors} />
      </div>
      <p className="text-xs text-ink-muted">
        Free API-Football plan cap is 100 requests/day. "API requests" above is every call that
        actually reached api-football.com (a cache hit costs nothing).
      </p>

      <FootballHubApiKeyForm
        configured={apiKeyStatus.configured}
        maskedKey={apiKeyStatus.maskedKey}
        keyUpdatedAtMs={apiKeyStatus.keyUpdatedAtMs}
        keyUpdatedByEmail={apiKeyStatus.keyUpdatedByEmail}
      />

      <FootballHubPollerToggle
        pollerEnabled={config.pollerEnabled}
        updatedAtMs={config.updatedAtMs}
        updatedByEmail={config.updatedByEmail}
      />
    </div>
  );
}
