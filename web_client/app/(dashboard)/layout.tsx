'use client';

import React from 'react';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { Glass } from '@/components/ui/Glass';
import { TopBar } from '@/components/ui/TopBar';
import { Activity, Trophy, User, Settings, LayoutDashboard, Store, Radio, Network } from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  const navItems = [
    { href: '/settings', icon: Settings, label: 'Settings' },
    { href: '/feed', icon: Activity, label: 'Feed' },
    { href: '/master-leagues/discovery', icon: Network, label: 'Discover' },
    { href: '/global-chat', icon: Radio, label: 'Global' },
    { href: '/leagues', icon: LayoutDashboard, label: 'Leagues' },
    { href: '/master-leagues', icon: Network, label: 'Hubs' },
    { href: '/live', icon: Radio, label: 'Live' },
    { href: '/marketplace', icon: Store, label: 'Market' },
    { href: '/profile', icon: User, label: 'Profile' },
  ];

  const BottomNav = (
    <Glass intensity="high" className="flex justify-around items-center p-3 rounded-t-3xl rounded-b-none border-b-0 border-x-0">
      {navItems.map((item) => {
        const isActive = pathname.startsWith(item.href);
        const Icon = item.icon;
        
        return (
          <Link key={item.href} href={item.href} className="flex flex-col items-center flex-1">
            <Icon 
              className={cn(
                "w-6 h-6 mb-1 transition-colors", 
                isActive ? "text-brand-lime" : "text-gray-400",
                item.label === 'Live' && isActive ? "animate-pulse text-brand-red" : ""
              )} 
            />
            <span className={cn(
              "text-[10px] sm:text-xs transition-colors",
              isActive ? (item.label === 'Live' ? "text-brand-red font-medium" : "text-brand-lime font-medium") : "text-gray-400"
            )}>
              {item.label}
            </span>
          </Link>
        );
      })}
    </Glass>
  );

  return (
    <GlassScaffold bottomNavigation={BottomNav}>
      <div className="pb-24 md:pb-0 pt-2">
        {/* Inject the TopBar here for Desktop visibility */}
        <TopBar />
        
        {children}
      </div>
    </GlassScaffold>
  );
}
