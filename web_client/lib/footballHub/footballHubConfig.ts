// lib/footballHub/footballHubConfig.ts
//
// Same NEXT_PUBLIC_WORKER_BASE_URL every other worker-calling lib file
// uses (see lib/payments/flutterwaveConfig.ts) -- Football Hub's backend
// is the same Cloudflare Worker the Flutter app calls, not a separate one.

function base(): string | null {
  const b = (process.env.NEXT_PUBLIC_WORKER_BASE_URL || '').trim();
  if (!b) return null;
  return b.replace(/\/$/, '');
}

function url(path: string): string | null {
  const b = base();
  return b ? `${b}${path}` : null;
}

export const footballHubUrls = {
  fixtures: () => url('/football/fixtures'),
  fixtureEvents: () => url('/football/fixture-events'),
  standings: () => url('/football/standings'),
  squad: () => url('/football/squad'),
  player: () => url('/football/player'),
  leagues: () => url('/football/leagues'),
};
