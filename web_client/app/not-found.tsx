'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { motion } from 'framer-motion';
import { Home, Trophy, LayoutDashboard, FlagTriangleRight, CircleDashed, Gamepad2 } from 'lucide-react';
import { auth } from '@/lib/firebase';
import { User } from 'firebase/auth';
import { NotFoundSearch } from '@/components/ui/NotFoundSearch';
import { SimpleFooter } from '@/components/ui/SimpleFooter';
import { LeagueCardSkeleton } from '@/components/leagues/LeagueCard';
import { AuthGateModal } from '@/components/auth/AuthGateModal';

export default function NotFound() {
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [authModalOpen, setAuthModalOpen] = useState(false);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((currentUser) => {
      setUser(currentUser);
    });
    return () => unsubscribe();
  }, []);

  const handleProtectedNavigation = (e: React.MouseEvent, path: string) => {
    e.preventDefault();
    if (user) {
      router.push(path);
    } else {
      setAuthModalOpen(true);
    }
  };

  return (
    <div className="min-h-screen bg-[#0F172A] flex flex-col font-sans overflow-x-hidden selection:bg-brand-lime selection:text-slate-900">
      
      {/* Background Graphic Elements */}
      <div className="fixed inset-0 z-0 pointer-events-none flex items-center justify-center overflow-hidden">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] md:w-[800px] md:h-[800px] rounded-full border border-brand-lime/10 shadow-[0_0_120px_rgba(182,255,0,0.05)]" />
        <div className="absolute top-0 bottom-0 left-1/2 -translate-x-1/2 w-px bg-brand-lime/10" />
        <div className="absolute -top-40 -right-40 w-[500px] h-[500px] bg-brand-lime/10 rounded-full blur-[120px]" />
        <div className="absolute -bottom-40 -left-40 w-[500px] h-[500px] bg-sky-500/10 rounded-full blur-[120px]" />
      </div>

      {/* Top Navigation Bar with Auth Buttons */}
      <header className="w-full relative z-40 px-6 py-6 md:py-8 flex items-center justify-between max-w-7xl mx-auto">
        <Link href="/" className="flex items-center gap-3 group">
          <div className="w-10 h-10 md:w-12 md:h-12 bg-brand-lime rounded-xl md:rounded-2xl flex items-center justify-center shadow-[0_0_20px_rgba(182,255,0,0.2)] group-hover:scale-105 transition-transform">
            <Gamepad2 className="w-6 h-6 md:w-7 md:h-7 text-slate-900" />
          </div>
          <span className="text-xl md:text-2xl font-black text-white tracking-tight">eSportlyic</span>
        </Link>
        
        <div className="flex items-center gap-3 md:gap-5">
          {!user && (
            <>
              <Link href="/login" className="text-sm font-bold text-slate-300 hover:text-white transition-colors">
                Log in
              </Link>
              <Link href="/login" className="px-5 py-2.5 bg-brand-lime text-slate-900 text-sm font-black rounded-xl hover:brightness-110 transition-all shadow-[0_0_20px_rgba(182,255,0,0.15)]">
                Sign up
              </Link>
            </>
          )}
        </div>
      </header>

      <main className="flex-1 w-full max-w-7xl mx-auto px-6 pt-10 md:pt-20 relative z-10 flex flex-col items-center">
        
        <div className="text-center w-full max-w-3xl mx-auto">
          <motion.div 
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ duration: 0.5, type: 'spring' }}
            className="inline-flex items-center justify-center w-20 h-20 md:w-24 md:h-24 rounded-3xl bg-brand-surface border border-white/10 shadow-[0_0_40px_rgba(0,0,0,0.5)] mb-8 relative"
          >
            <div className="absolute inset-0 rounded-3xl border border-brand-lime/30 animate-pulse" />
            <FlagTriangleRight className="w-10 h-10 md:w-12 md:h-12 text-brand-lime" />
          </motion.div>

          <motion.h1 
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: 0.1, duration: 0.5 }}
            className="text-4xl md:text-6xl lg:text-7xl font-black text-white tracking-tight leading-tight"
          >
            Match <span className="text-brand-lime">Not Found</span>
          </motion.h1>
          
          <motion.p 
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: 0.2, duration: 0.5 }}
            className="mt-6 text-base md:text-lg text-slate-400 font-medium max-w-xl mx-auto leading-relaxed"
          >
            Looks like this competition has gone offside. The page you are looking for might have been moved, deleted, or never existed in the first place.
          </motion.p>
        </div>

        <NotFoundSearch />

        <motion.div 
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="grid grid-cols-1 md:grid-cols-3 gap-4 w-full max-w-4xl mx-auto mt-12"
        >
          <Link 
            href="/leagues" 
            className="group relative flex flex-col items-center justify-center p-6 bg-brand-surface border border-white/5 hover:border-brand-lime/30 rounded-3xl transition-all hover:bg-white/[0.03] overflow-hidden"
          >
            <Trophy className="w-8 h-8 text-slate-300 group-hover:text-brand-lime transition-colors mb-3" />
            <span className="text-white font-bold tracking-wide">Browse Leagues</span>
            <span className="text-xs text-slate-500 mt-1">Find active competitions</span>
          </Link>

          <button 
            onClick={(e) => handleProtectedNavigation(e, '/dashboard')}
            className="group relative flex flex-col items-center justify-center p-6 bg-brand-lime border border-brand-lime rounded-3xl transition-all hover:brightness-105 shadow-[0_0_30px_rgba(182,255,0,0.15)] overflow-hidden"
          >
            <LayoutDashboard className="w-8 h-8 text-slate-900 mb-3" />
            <span className="text-slate-900 font-black tracking-wide">My Dashboard</span>
            <span className="text-slate-700 font-semibold text-xs mt-1 text-center">Manage your teams</span>
          </button>

          <Link 
            href="/" 
            className="group relative flex flex-col items-center justify-center p-6 bg-brand-surface border border-white/5 hover:border-white/20 rounded-3xl transition-all hover:bg-white/[0.03] overflow-hidden"
          >
            <Home className="w-8 h-8 text-slate-300 group-hover:text-white transition-colors mb-3" />
            <span className="text-white font-bold tracking-wide">Return Home</span>
            <span className="text-xs text-slate-500 mt-1">Back to the starting whistle</span>
          </Link>
        </motion.div>

        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.6, duration: 0.8 }}
          className="w-full max-w-7xl mx-auto mt-24 md:mt-32"
        >
          <div className="flex items-center gap-3 mb-8">
            <CircleDashed className="w-5 h-5 text-brand-lime animate-[spin_4s_linear_infinite]" />
            <h2 className="text-xl md:text-2xl font-black text-white">Trending Competitions</h2>
            <div className="flex-1 h-px bg-gradient-to-r from-white/10 to-transparent ml-4" />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            <LeagueCardSkeleton />
            <LeagueCardSkeleton />
            <div className="hidden lg:block"><LeagueCardSkeleton /></div>
          </div>
        </motion.div>
      </main>

      <SimpleFooter />

      {/* Reusable Interceptor */}
      <AuthGateModal 
        isOpen={authModalOpen} 
        onClose={() => setAuthModalOpen(false)} 
      />

    </div>
  );
}
