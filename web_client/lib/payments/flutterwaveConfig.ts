export const FlutterwaveConfig = {
  publicKey: (process.env.NEXT_PUBLIC_FLUTTERWAVE_PUBLIC_KEY || '').trim(),
  redirectUrl:
    (process.env.NEXT_PUBLIC_APP_BASE_URL || 'https://esportlyic.web.app').trim() +
    '/payments/callback',
  isTestMode: (process.env.NEXT_PUBLIC_FLUTTERWAVE_TEST_MODE || '').trim() === 'true',

  assertConfigured(): void {
    if (!this.publicKey) {
      throw new Error(
        'Flutterwave is not configured. Missing NEXT_PUBLIC_FLUTTERWAVE_PUBLIC_KEY.',
      );
    }
  },
};

export function workerFlutterwaveVerifyUrl(): string | null {
  const base = (process.env.NEXT_PUBLIC_WORKER_BASE_URL || '').trim();
  if (!base) return null;
  return `${base.replace(/\/$/, '')}/flutterwave/verify`;
}
