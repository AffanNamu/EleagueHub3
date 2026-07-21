'use client';

import { Sun, Moon } from 'lucide-react';
import { useTheme } from '@/components/providers/ClientThemeProvider';

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="w-10 h-10 rounded-xl flex items-center justify-center bg-white/5 border border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-400 hover:text-brand-lime dark:hover:text-brand-lime transition-all hover:bg-slate-100 dark:hover:bg-white/5 shadow-sm"
      aria-label="Toggle Theme"
    >
      {theme === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5 text-slate-800" />}
    </button>
  );
}
