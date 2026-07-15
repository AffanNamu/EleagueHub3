'use client';

import React, { useEffect, useState } from 'react';
import { useThemeStore } from '@/store/themeStore';

export const ClientThemeProvider = ({ children }: { children: React.ReactNode }) => {
  const [mounted, setMounted] = useState(false);
  const isDarkMode = useThemeStore((state) => state.isDarkMode);

  useEffect(() => {
    setMounted(true);
    if (isDarkMode) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  }, [isDarkMode]);

  if (!mounted) {
    return <>{children}</>;
  }

  return <>{children}</>;
};
