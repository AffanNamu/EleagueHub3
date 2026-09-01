// lib/countryResolver.ts
//
// Web counterpart to core/services/country/country_resolver_service.dart.
// The Flutter app resolves the signed-in user's country via native
// platform APIs (see country_resolver_io.dart / country_resolver_web.dart).
// There's no equivalent native signal in a browser, so this uses a public
// IP-geolocation lookup instead — this is exactly the approach the
// original app/(dashboard)/search/page.tsx comment already flagged
// ("you might hit an IP API like 'https://ipapi.co/json/'") but never
// actually wired up, leaving the web "Teams Near You" section hardcoded
// to 'US' for every user regardless of where they are.
//
// Always resolves to an uppercase 2-letter country code, falling back to
// 'US' on any failure (network error, timeout, rate limit) so callers
// never have to special-case an empty/unknown result.

const FALLBACK_COUNTRY = 'US';
const REQUEST_TIMEOUT_MS = 6000;

export async function resolveCountryCodeWeb(): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const res = await fetch('https://ipapi.co/json/', { signal: controller.signal });
    if (!res.ok) return FALLBACK_COUNTRY;

    const data = await res.json();
    const code = (data?.country_code ?? data?.country ?? '').toString().trim().toUpperCase();

    if (code.length === 2) return code;
    return FALLBACK_COUNTRY;
  } catch (err) {
    console.error('[countryResolver] resolveCountryCodeWeb failed, defaulting to', FALLBACK_COUNTRY, err);
    return FALLBACK_COUNTRY;
  } finally {
    clearTimeout(timeout);
  }
}
