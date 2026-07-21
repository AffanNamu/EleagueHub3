'use client';

import React, { useState } from 'react';
import { TopBar } from '@/components/ui/TopBar';
import {
  Activity, Trophy, User, Settings, LayoutDashboard,
  Store, Radio, Network, MessageSquare, Crown, X
} from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  
  // State to handle hiding the Premium Ad card
  const [showPremiumAd, setShowPremiumAd] = useState(true);

  // Mapped to your existing routes, but styled to match the new premium sidebar
  const navItems = [
    { href: '/master-leagues', icon: LayoutDashboard, label: 'Dashboard' },
    { href: '/leagues', icon: Trophy, label: 'Competitions' },
    { href: '/feed', icon: Activity, label: 'Feed' },
    { href: '/master-leagues/discovery', icon: Network, label: 'Discover' },
    { href: '/global-chat', icon: MessageSquare, label: 'Global Chat' },
    { href: '/live', icon: Radio, label: 'Live Matches' },
    { href: '/marketplace', icon: Store, label: 'Marketplace' },
    { href: '/profile', icon: User, label: 'Profile' },
    { href: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <div className="flex h-screen bg-[#070B14] text-white overflow-hidden font-sans">
      
      {/* DESKTOP SIDEBAR (Matches your mockup) */}
      <aside className="hidden md:flex flex-col w-64 bg-[#0B1221] border-r border-[#1E293B] h-full flex-shrink-0 z-20">
        {/* Logo Area */}
        <div className="p-6 flex items-center gap-3">
          <div className="w-8 h-8 bg-brand-lime rounded-lg flex items-center justify-center shadow-lg shadow-brand-lime/20">
            <Network className="w-5 h-5 text-brand-navy" />
          </div>
          <span className="text-xl font-black tracking-wide text-white">eSportlyic</span>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 overflow-y-auto px-4 py-2 space-y-1 custom-scrollbar">
          {navItems.map((item) => {
            // Strict exact match for the root dashboard, startsWith for sub-pages
            const isActive = pathname === item.href || (pathname.startsWith(item.href) && item.href !== '/master-leagues');
            const Icon = item.icon;
            
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-bold transition-all duration-200",
                  isActive
                    ? "bg-brand-lime text-brand-navy shadow-[0_0_15px_rgba(184,233,40,0.15)]"
                    : "text-gray-400 hover:text-white hover:bg-white/5"
                )}
              >
                <Icon className={cn("w-5 h-5", isActive ? "text-brand-navy" : "text-gray-400")} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        {/* Premium Upgrade Card (Now with a dismiss button!) */}
        {showPremiumAd && (
          <div className="p-4 mt-auto">
            <div className="bg-[#0F172A] border border-[#1E293B] p-5 rounded-2xl text-center flex flex-col items-center relative">
              {/* Dismiss X Button */}
              <button 
                onClick={() => setShowPremiumAd(false)}
                className="absolute top-2 right-2 p-1 text-gray-500 hover:text-white bg-[#1E293B]/50 hover:bg-[#1E293B] rounded-full transition-colors"
                title="Dismiss"
              >
                <X className="w-4 h-4" />
              </button>

              <Crown className="w-8 h-8 text-amber-400 mb-2 drop-shadow-md mt-2" />
              <h4 className="text-white font-bold text-sm">Upgrade to<br/>Premium Organizer</h4>
              <p className="text-xs text-gray-400 mt-2 mb-4 leading-relaxed">
                Get more visibility, advanced analytics and exclusive features.
              </p>
              <Link href="/master-leagues/create" className="w-full py-2.5 bg-brand-lime text-brand-navy font-bold text-xs rounded-lg hover:brightness-110 transition-all shadow-lg shadow-brand-lime/10 block">
                Upgrade Now &rarr;
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

        {/* MOBILE BOTTOM NAV (Hidden on Desktop) */}
        <div className="md:hidden bg-[#0B1221] border-t border-[#1E293B] flex justify-around items-center p-3 pb-safe z-50">
          {navItems.slice(0, 5).map((item) => {
            const isActive = pathname === item.href || (pathname.startsWith(item.href) && item.href !== '/master-leagues');
            const Icon = item.icon;
            
            return (
              <Link key={item.href} href={item.href} className="flex flex-col items-center flex-1 gap-1">
                <Icon
                  className={cn(
                    "w-5 h-5 transition-colors",
                    isActive ? "text-brand-lime" : "text-gray-500",
                    item.label === 'Live Matches' && isActive ? "animate-pulse text-brand-red" : ""
                  )}
                />
                <span className={cn(
                  "text-[10px] font-bold transition-colors",
                  isActive ? "text-brand-lime" : "text-gray-500"
                )}>
                  {item.label.split(' ')[0]}
                </span>
              </Link>
            );
          })}
        </div>
      </main>
    </div>
  );
}
