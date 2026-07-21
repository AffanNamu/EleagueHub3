'use client';

import { useEffect, useState } from 'react';

export type DeviceMode = 'mobile' | 'desktop';

const DESKTOP_BREAKPOINT = 900;

function computeDeviceMode(): DeviceMode {
  if (typeof window === 'undefined') return 'desktop';
  return window.innerWidth >= DESKTOP_BREAKPOINT ? 'desktop' : 'mobile';
}

export function useDeviceMode(): DeviceMode | null {
  const [mode, setMode] = useState<DeviceMode | null>(null);

  useEffect(() => {
    setMode(computeDeviceMode());

    let frame = 0;
    const onResize = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => setMode(computeDeviceMode()));
    };

    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', onResize);

    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('orientationchange', onResize);
      cancelAnimationFrame(frame);
    };
  }, []);

  return mode;
}
