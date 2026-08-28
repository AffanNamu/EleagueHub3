'use client';

import React, { useState } from 'react';
import { TopBar } from '@/components/ui/TopBar';
import {
  Home, Trophy, User, Settings, LayoutDashboard,
  Store, Network, MessageSquare, Crown, X, Compass
} from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  
  const [showPremiumAd, setShowPremiumAd] = useState(true);

  // Desktop Sidebar Navigation (Expanded for larger screens)
  const desktopNavItems = [
    { href: '/', icon: Home, label: 'Home' },
    { href: '/leagues', icon: Trophy, label: 'Competitions' },
    { href: '/master-leagues', icon: LayoutDashboard, label: 'Workspaces' },
    { href: '/discovery/community', icon: MessageSquare, label: 'Community' },
    { href: '/marketplace', icon: Store, label: 'Marketplace' },
    { href: '/profile', icon: User, label: 'Profile' },
    { href: '/settings', icon: Settings, label: 'Settings' },
  ];

  // Mobile Bottom Navigation (Strictly matches Flutter HomeShell's 5 tabs)
  const mobileNavItems = [
    { href: '/', icon: Home, label: 'Home' },
    { href: '/leagues', icon: Trophy, label: 'Leagues' },
    { href: '/discovery/community', icon: Compass, label: 'Discover' },
    { href: '/marketplace', icon: Store, label: 'Market' },
    { href: '/profile', icon: User, label: 'Profile' },
  ];

  // Helper to determine active state precisely
  const isActiveRoute = (itemHref: string) => {
    if (itemHref === '/') {
      return pathname === '/';
    }
    return pathname === itemHref || pathname.startsWith(`${itemHref}/`);
  };

  return (
    <div className="flex h-screen bg-[#070B14] text-white overflow-hidden font-sans">
      
      {/* DESKTOP SIDEBAR */}
      <aside className="hidden md:flex flex-col w-64 bg-[#0B1221] border-r border-[#1E293B] h-full flex-shrink-0 z-20">
        {/* Logo Area */}
        <div className="p-6 flex items-center gap-3">
          <div className="w-8 h-8 bg-[#BEF264] rounded-lg flex items-center justify-center shadow-lg shadow-[#BEF264]/20">
            <Network className="w-5 h-5 text-[#0F172A]" />
          </div>
          <span className="text-xl font-black tracking-wide text-white">eSportlyic</span>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 overflow-y-auto px-4 py-2 space-y-1 custom-scrollbar">
          {desktopNavItems.map((item) => {
            const isActive = isActiveRoute(item.href);
            const Icon = item.icon;
            
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-bold transition-all duration-200",
                  isActive
                    ? "bg-[#BEF264] text-[#0F172A] shadow-[0_0_15px_rgba(190,242,100,0.15)]"
                    : "text-gray-400 hover:text-white hover:bg-white/5"
                )}
              >
                <Icon className={cn("w-5 h-5", isActive ? "text-[#0F172A]" : "text-gray-400")} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        {/* Premium Upgrade Card */}
        {showPremiumAd && (
          <div className="p-4 mt-auto">
            <div className="bg-[#0F172A] border border-[#1E293B] p-5 rounded-2xl text-center flex flex-col items-center relative">
              <button 
                onClick={() => setShowPremiumAd(false)}
                className="absolute top-2 right-2 p-1 text-gray-500 hover:text-white bg-[#1E293B]/50 hover:bg-[#1E293B] rounded-full transition-colors"
                title="Dismiss"
              >
                <X className="w-4 h-4" />
              </button>

              <Crown className="w-8 h-8 text-amber-400 mb-2 drop-shadow-md mt-2" />
              <h4 className="text-white font-bold text-sm">Upgrade Plan</h4>
              <p className="text-xs text-gray-400 mt-2 mb-4 leading-relaxed">
                Unlock advanced league management and premium features.
              </p>
              <Link href="/premium" className="w-full py-2.5 bg-[#BEF264] text-[#0F172A] font-bold text-xs rounded-lg hover:brightness-110 transition-all shadow-lg shadow-[#BEF264]/10 block">
                View Plans &rarr;
              </Link>
            </div>
          </div>
        )}
      </aside>

      {/* MAIN CONTENT AREA */}
      <main className="flex-1 flex flex-col h-full overflow-hidden relative">
        <TopBar />
        
        {/* Scrollable Page Content */}
        <div className="flex-1 overflow-y-auto p-4 md:p-6 lg:p-8 relative">
          {children}
        </div>

        {/* MOBILE BOTTOM NAV */}
        <div className="md:hidden bg-[#0B1221] border-t border-[#1E293B] flex justify-around items-center p-2 pb-safe z-50">
          {mobileNavItems.map((item) => {
            const isActive = isActiveRoute(item.href);
            const Icon = item.icon;
            
            return (
              <Link key={item.href} href={item.href} className="flex flex-col items-center flex-1 gap-1 py-1">
                <Icon
                  className={cn(
                    "w-6 h-6 transition-colors",
                    isActive ? "text-[#BEF264]" : "text-gray-500"
                  )}
                />
                <span className={cn(
                  "text-[10px] font-bold transition-colors",
                  isActive ? "text-[#BEF264]" : "text-gray-500"
                )}>
                  {item.label}
                </span>
              </Link>
            );
          })}
        </div>
      </main>
    </div>
  );
}
