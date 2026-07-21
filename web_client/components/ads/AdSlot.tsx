'use client';

import { useEffect, useRef } from 'react';

const CLIENT_ID = (process.env.NEXT_PUBLIC_ADSENSE_CLIENT_ID || '').trim();

declare global {
  interface Window {
    adsbygoogle?: unknown[];
  }
}

/**
 * A single AdSense display unit. Pass the ad slot id from your AdSense
 * dashboard (Ads > By ad unit). Renders nothing if AdSense isn't
 * configured, so pages don't break in environments without it.
 */
export function AdSlot({
  slot,
  format = 'auto',
  className = '',
}: {
  slot: string;
  format?: string;
  className?: string;
}) {
  const ref = useRef<HTMLModElement>(null);

  useEffect(() => {
    if (!CLIENT_ID || !slot) return;
    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({});
    } catch (e) {
      console.warn('[AdSlot] adsbygoogle push failed:', e);
    }
  }, [slot]);

  if (!CLIENT_ID || !slot) return null;

  return (
    <ins
      ref={ref}
      className={`adsbygoogle block ${className}`}
      style={{ display: 'block' }}
      data-ad-client={CLIENT_ID}
      data-ad-slot={slot}
      data-ad-format={format}
      data-full-width-responsive="true"
    />
  );
}
