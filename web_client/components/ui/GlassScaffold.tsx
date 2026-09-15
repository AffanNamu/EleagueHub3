import React from 'react';
import { useTheme } from '@/components/providers/ClientThemeProvider';
import { cn } from '@/lib/utils';

interface GlassScaffoldProps {
  children: React.ReactNode;
  appBar?: React.ReactNode;
  bottomNavigation?: React.ReactNode;
}

export const GlassScaffold: React.FC<GlassScaffoldProps> = ({
  children,
  appBar,
  bottomNavigation,
}) => {
  const { theme } = useTheme();
  const isDarkMode = theme === 'dark';

  return (
    <div
      className={cn(
        'min-h-screen w-full flex flex-col transition-colors duration-300',
        isDarkMode ? 'bg-brand-navy text-white' : 'bg-white text-slate-900'
      )}
    >
      {appBar && <header className="sticky top-0 z-50 w-full">{appBar}</header>}
      
      <main className="flex-1 w-full max-w-7xl mx-auto p-4 md:p-6 lg:p-8">
        {children}
      </main>

      {bottomNavigation && (
        <footer className="fixed bottom-0 w-full z-50 md:hidden">
          {bottomNavigation}
        </footer>
      )}
    </div>
  );
};
