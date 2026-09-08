import { Share2 } from 'lucide-react';
import type { ChannelBreakdownRow } from '@/types/linkAnalytics';

const CHANNEL_LABEL: Record<string, string> = {
  whatsapp: 'WhatsApp',
  telegram: 'Telegram',
  facebook: 'Facebook',
  x: 'X (Twitter)',
  sms: 'SMS',
  copy_link: 'Copied Link',
  system_share: 'System Share Sheet',
  deep_link: 'Deep Link',
  web_direct: 'Web (Direct)',
};

export function ShareChannelBreakdownCard({ rows }: { rows: ChannelBreakdownRow[] }) {
  const maxTotal = Math.max(1, ...rows.map((r) => r.shares + r.clicks));

  return (
    <div className="panel p-5">
      <div className="mb-4 flex items-center gap-2">
        <Share2 size={16} className="text-ink-secondary" />
        <h2 className="font-display text-sm font-semibold text-ink-primary">Sharing by Channel</h2>
      </div>

      {rows.length === 0 ? (
        <p className="text-sm text-ink-secondary">No share/click activity recorded yet.</p>
      ) : (
        <div className="space-y-2.5">
          {rows.map((row) => (
            <div key={row.channel}>
              <div className="mb-1 flex items-center justify-between text-sm">
                <span className="text-ink-secondary">{CHANNEL_LABEL[row.channel] ?? row.channel}</span>
                <span className="text-ink-primary">
                  {row.shares} shares · {row.clicks} clicks
                </span>
              </div>
              <div className="flex h-1.5 overflow-hidden rounded-full bg-base-raised">
                <div
                  className="h-full bg-brand"
                  style={{ width: `${(row.shares / maxTotal) * 100}%` }}
                />
                <div
                  className="h-full bg-signal-info"
                  style={{ width: `${(row.clicks / maxTotal) * 100}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
