'use client';

import Script from 'next/script';

const CLIENT_ID = (process.env.NEXT_PUBLIC_ADSENSE_CLIENT_ID || '').trim();

/**
 * Loads the global AdSense script once, site-wide. Put this in your root
 * layout.tsx inside <body> (once). If NEXT_PUBLIC_ADSENSE_CLIENT_ID isn't
 * set, this renders nothing — safe for local dev without an approved
 * AdSense account.
 */
export function AdSenseScript() {
  if (!CLIENT_ID) return null;

  return (
    <Script
      async
      src={`https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${CLIENT_ID}`}
      crossOrigin="anonymous"
      strategy="afterInteractive"
    />
  );
}
