import type { BuildInfo } from '@/lib/buildInfo';

function Row({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex items-center justify-between border-b border-base-border px-4 py-2.5 last:border-0">
      <span className="text-sm text-ink-secondary">{label}</span>
      <span className={`font-mono text-sm ${value ? 'text-ink-primary' : 'text-ink-muted'}`}>
        {value ?? 'unavailable'}
      </span>
    </div>
  );
}

export function BuildInfoPanel({ info }: { info: BuildInfo }) {
  return (
    <div className="panel overflow-hidden">
      <div className="border-b border-base-border px-4 py-3">
        <h2 className="font-display text-sm font-semibold text-ink-primary">Build Info</h2>
        <p className="mt-0.5 text-xs text-ink-secondary">
          Read directly from this deployment's own checkout — "unavailable" means that
          sub-project's files weren't bundled with this deployment, not that it has no version.
        </p>
      </div>
      <Row label="Mobile app (pubspec.yaml)" value={info.mobileAppVersion} />
      <Row label="Web client (package.json)" value={info.webClientVersion} />
      <Row label="Admin panel (package.json)" value={info.adminVersion} />
      <Row label="Worker (package.json)" value={info.workerVersion} />
      <Row label="Deployed commit" value={info.gitCommitSha} />
    </div>
  );
}
