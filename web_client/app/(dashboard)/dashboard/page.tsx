'use client';

import React, { useEffect, useState } from 'react';
import { Glass } from '@/components/ui/Glass';
import { 
  Trophy, Gamepad2, Users, ArrowRight, Activity, 
  ChevronRight, Swords, Radio, Plus, QrCode, Loader2
} from 'lucide-react';
import Link from 'next/link';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { usePlatformAnnouncements } from '@/hooks/usePlatformAnnouncements';
import { formatDistanceToNow } from 'date-fns';

export default function DashboardHomeScreen() {
  const [userName, setUserName] = useState<string>('Commander');
  const { announcements, loading: commsLoading } = usePlatformAnnouncements(3);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (user) => {
      if (user && user.displayName) {
        setUserName(user.displayName.split(' ')[0]);
      }
    });
    return () => unsub();
  }, []);

  const currentDate = new Date().toLocaleDateString('en-US', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  });

  return (
    <div className="max-w-7xl mx-auto space-y-8 pb-20">
      
      {/* 1. WELCOME HEADER & STATS MATRIX */}
      <div className="flex flex-col lg:flex-row gap-6 lg:items-end justify-between">
        <div>
          <h1 className="text-3xl md:text-4xl font-black text-white tracking-tight flex items-center gap-3">
            Welcome back, {userName} <span className="animate-pulse">⚡</span>
          </h1>
          <p className="text-gray-400 mt-2 font-medium">{currentDate} — Your command center is ready.</p>
        </div>

        {/* High-Level Data Nodes */}
        <div className="flex items-center gap-3 md:gap-4 overflow-x-auto pb-2 custom-scrollbar">
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 flex items-center gap-4 min-w-[160px]">
            <div className="w-12 h-12 rounded-xl bg-brand-lime/10 border border-brand-lime/20 flex items-center justify-center shrink-0">
              <Gamepad2 className="w-6 h-6 text-brand-lime" />
            </div>
            <div>
              <p className="text-xs text-gray-500 font-bold uppercase tracking-wider mb-0.5">Active Matches</p>
              <p className="text-2xl font-black text-white leading-none">0</p>
            </div>
          </div>

          <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 flex items-center gap-4 min-w-[160px]">
            <div className="w-12 h-12 rounded-xl bg-[#38BDF8]/10 border border-[#38BDF8]/20 flex items-center justify-center shrink-0">
              <Trophy className="w-6 h-6 text-[#38BDF8]" />
            </div>
            <div>
              <p className="text-xs text-gray-500 font-bold uppercase tracking-wider mb-0.5">Tournaments</p>
              <p className="text-2xl font-black text-white leading-none">0</p>
            </div>
          </div>

          <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 flex items-center gap-4 min-w-[160px]">
            <div className="w-12 h-12 rounded-xl bg-[#A78BFA]/10 border border-[#A78BFA]/20 flex items-center justify-center shrink-0">
              <Users className="w-6 h-6 text-[#A78BFA]" />
            </div>
            <div>
              <p className="text-xs text-gray-500 font-bold uppercase tracking-wider mb-0.5">Communities</p>
              <p className="text-2xl font-black text-white leading-none">0</p>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        
        {/* LEFT COLUMN: Hero Focus & Fixtures */}
        <div className="xl:col-span-2 space-y-6">
          <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#0B1221] to-[#070B14] border border-[#1E293B] p-8 group">
            <div className="absolute top-0 right-0 w-64 h-64 bg-brand-lime/10 blur-[80px] rounded-full pointer-events-none group-hover:bg-brand-lime/20 transition-all duration-700"></div>
            <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
              <div className="space-y-4 max-w-lg">
                <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-brand-lime/10 border border-brand-lime/20 text-brand-lime text-xs font-black uppercase tracking-widest">
                  <Radio className="w-3 h-3 animate-pulse" /> Platform Ready
                </div>
                <h2 className="text-3xl md:text-4xl font-black text-white tracking-tight leading-tight">
                  No Active Tournaments
                </h2>
                <p className="text-gray-400 font-medium">
                  Create a new tournament or join an existing arena to start competing on the global circuit.
                </p>
                <div className="pt-2">
                  <Link href="/leagues/create" className="inline-flex items-center gap-2 px-6 py-3 bg-brand-lime text-[#070B14] font-black rounded-xl hover:brightness-110 transition-all shadow-[0_0_20px_rgba(182,255,0,0.15)]">
                    Create Tournament <ArrowRight className="w-4 h-4" />
                  </Link>
                </div>
              </div>
            </div>
          </div>

          <Glass className="p-1 md:p-6 border border-[#1E293B]">
            <div className="flex items-center justify-between mb-6 px-3 md:px-0">
              <h3 className="text-lg font-black text-white flex items-center gap-2">
                <Swords className="w-5 h-5 text-brand-lime" /> Action Feed
              </h3>
            </div>
            <div className="flex flex-col items-center justify-center py-10 text-center">
              <Gamepad2 className="w-12 h-12 text-[#1E293B] mb-3" />
              <p className="text-gray-500 font-bold">No recent match activity.</p>
              <p className="text-xs text-gray-600 mt-1">Matches will appear here once competitions begin.</p>
            </div>
          </Glass>
        </div>

        {/* RIGHT COLUMN: Action Matrix & Comms */}
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3">
            <Link href="/leagues/create" className="flex flex-col items-center justify-center p-6 rounded-2xl bg-gradient-to-b from-[#0B1221] to-[#070B14] border border-[#1E293B] hover:border-brand-lime/50 transition-all group">
              <div className="w-10 h-10 rounded-full bg-brand-lime/10 flex items-center justify-center mb-3 group-hover:scale-110 transition-transform">
                <Plus className="w-5 h-5 text-brand-lime" />
              </div>
              <span className="text-sm font-bold text-white text-center">New<br/>Tournament</span>
            </Link>
            
            <Link href="/leagues/join-scanner" className="flex flex-col items-center justify-center p-6 rounded-2xl bg-gradient-to-b from-[#0B1221] to-[#070B14] border border-[#1E293B] hover:border-[#38BDF8]/50 transition-all group">
              <div className="w-10 h-10 rounded-full bg-[#38BDF8]/10 flex items-center justify-center mb-3 group-hover:scale-110 transition-transform">
                <QrCode className="w-5 h-5 text-[#38BDF8]" />
              </div>
              <span className="text-sm font-bold text-white text-center">Join<br/>Arena</span>
            </Link>

            <Link href="/master-leagues/discovery" className="col-span-2 flex items-center justify-between p-4 rounded-2xl bg-gradient-to-r from-[#1A103C] to-[#0F0B1E] border border-[#3B2568] hover:brightness-110 transition-all">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-[#A78BFA]/20 flex items-center justify-center">
                  <Users className="w-4 h-4 text-[#A78BFA]" />
                </div>
                <span className="text-sm font-bold text-white">Discover Communities</span>
              </div>
              <ChevronRight className="w-4 h-4 text-gray-400" />
            </Link>
          </div>

          {/* REAL-TIME GLOBAL COMMS */}
          <Glass className="p-5 border border-[#1E293B]">
            <div className="flex items-center justify-between mb-5">
              <div className="flex items-center gap-2">
                <Activity className="w-4 h-4 text-[#A78BFA]" />
                <h3 className="text-sm font-black text-white uppercase tracking-wider">System Comms</h3>
              </div>
              {auth.currentUser?.uid === 'a0JDUelQW3TEyoXTm4ESuGi7ndq1' && (
                <Link href="/admin" className="text-[10px] bg-[#1E293B] text-white px-2 py-1 rounded font-bold uppercase tracking-wider hover:bg-brand-red transition-colors">Post</Link>
              )}
            </div>
            
            <div className="space-y-4">
              {commsLoading ? (
                <div className="flex justify-center py-6">
                  <Loader2 className="w-6 h-6 animate-spin text-[#A78BFA]" />
                </div>
              ) : announcements.length === 0 ? (
                <div className="text-center py-6">
                  <p className="text-xs text-gray-500 font-medium">All systems operational.</p>
                </div>
              ) : (
                announcements.map((ann) => {
                  let colorClass = 'bg-[#A78BFA]';
                  let textClass = 'text-[#A78BFA]';
                  let typeLabel = 'Platform Update';

                  if (ann.type === 'alert') {
                    colorClass = 'bg-brand-lime';
                    textClass = 'text-brand-lime';
                    typeLabel = 'Event Alert';
                  } else if (ann.type === 'maintenance') {
                    colorClass = 'bg-brand-red';
                    textClass = 'text-brand-red';
                    typeLabel = 'System Alert';
                  }

                  return (
                    <div key={ann.id} className="p-4 rounded-xl bg-[#070B14] border border-[#1E293B] relative overflow-hidden">
                      <div className={`absolute left-0 top-0 bottom-0 w-1 ${colorClass}`}></div>
                      <p className={`text-[10px] ${textClass} font-black mb-1.5 tracking-widest uppercase`}>{typeLabel}</p>
                      <h4 className="text-sm font-bold text-white mb-2 leading-snug">{ann.title}</h4>
                      <p className="text-xs text-gray-400 leading-relaxed whitespace-pre-wrap">{ann.message}</p>
                      <p className="text-[10px] text-gray-600 font-bold mt-3 tracking-wider uppercase">
                        {formatDistanceToNow(ann.createdAtMs)} AGO
                      </p>
                    </div>
                  );
                })
              )}
            </div>
          </Glass>
        </div>
      </div>
    </div>
  );
}
