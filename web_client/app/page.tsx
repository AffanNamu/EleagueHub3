/*app/page.tsx*/
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Gamepad2, Trophy, Shield, TrendingUp, ArrowRight, CircleDashed } from 'lucide-react';
import { auth } from '@/lib/firebase';
import { User } from 'firebase/auth';
import { SimpleFooter } from '@/components/ui/SimpleFooter';
import { LeagueCardSkeleton } from '@/components/leagues/LeagueCard';

export default function HomePage() {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((currentUser) => {
      setUser(currentUser);
    });
    return () => unsubscribe();
  }, []);

  return (
    <div className="min-h-screen bg-[#081120] flex flex-col font-sans overflow-x-hidden selection:bg-brand-lime selection:text-slate-900">
      
      {/* Navbar */}
      <header className="w-full fixed top-0 z-50 bg-[#081120]/80 backdrop-blur-md border-b border-white/5">
        <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-3 group">
            <div className="w-10 h-10 bg-brand-lime rounded-xl flex items-center justify-center shadow-[0_0_20px_rgba(182,255,0,0.2)] group-hover:scale-105 transition-transform">
              <Gamepad2 className="w-6 h-6 text-slate-900" />
            </div>
            <span className="text-2xl font-black text-white tracking-tight">eSportlyic</span>
          </Link>
          
          <div className="flex items-center gap-4">
            {user ? (
              <Link href="/dashboard" className="px-5 py-2.5 bg-brand-lime text-slate-900 text-sm font-black rounded-xl hover:brightness-110 transition-all shadow-[0_0_20px_rgba(182,255,0,0.15)] flex items-center gap-2">
                Dashboard <ArrowRight className="w-4 h-4" />
              </Link>
            ) : (
              <>
                <Link href="/login" className="hidden md:block text-sm font-bold text-slate-300 hover:text-white transition-colors">
                  Log in
                </Link>
                <Link href="/login" className="px-5 py-2.5 bg-brand-lime text-slate-900 text-sm font-black rounded-xl hover:brightness-110 transition-all shadow-[0_0_20px_rgba(182,255,0,0.15)]">
                  Get Started
                </Link>
              </>
            )}
          </div>
        </div>
      </header>

      <main className="flex-1 w-full flex flex-col items-center pt-20">
        
        {/* HERO SECTION */}
        <section className="relative w-full min-h-[80vh] flex flex-col items-center justify-center px-6 py-20 overflow-hidden">
          <div className="absolute inset-0 z-0 pointer-events-none flex items-center justify-center">
            <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[800px] h-[400px] bg-brand-lime/20 rounded-[100%] blur-[120px]" />
            <div className="absolute bottom-0 w-full h-[300px] bg-gradient-to-t from-[#081120] to-transparent z-10" />
            <div className="absolute inset-0 bg-[linear-gradient(to_right,#ffffff0a_1px,transparent_1px),linear-gradient(to_bottom,#ffffff0a_1px,transparent_1px)] bg-[size:4rem_4rem] [mask-image:radial-gradient(ellipse_60%_50%_at_50%_50%,#000_70%,transparent_100%)]" />
          </div>

          <div className="relative z-10 w-full max-w-5xl mx-auto text-center flex flex-col items-center">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5 }}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 border border-white/10 text-brand-lime text-xs font-black uppercase tracking-widest mb-8 backdrop-blur-sm"
            >
              <Trophy className="w-4 h-4" />
              The Ultimate League Management App
            </motion.div>

            <motion.h1 
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: 0.1 }}
              className="text-6xl md:text-8xl font-black text-white tracking-tighter leading-[0.9] uppercase italic"
            >
              Manage.<br />
              Compete.<br />
              <span className="text-brand-lime drop-shadow-[0_0_30px_rgba(182,255,0,0.3)]">Win.</span>
            </motion.h1>

            <motion.p 
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: 0.2 }}
              className="mt-8 text-lg md:text-xl text-slate-400 font-medium max-w-2xl mx-auto leading-relaxed"
            >
              Create competitions, manage teams, and track every stage of your tournament. Whether it's EA SPORTS FC, eFootball, or Local Football.
            </motion.p>

            <motion.div 
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: 0.3 }}
              className="mt-10 flex flex-col sm:flex-row items-center gap-4 w-full sm:w-auto"
            >
              <Link href={user ? "/leagues/create" : "/login"} className="w-full sm:w-auto px-8 py-4 bg-brand-lime text-slate-900 text-lg font-black rounded-2xl hover:brightness-110 transition-all shadow-[0_0_30px_rgba(182,255,0,0.2)] flex items-center justify-center gap-2 group">
                Create Your League
                <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform" />
              </Link>
              <Link href="/leagues" className="w-full sm:w-auto px-8 py-4 bg-white/5 text-white border border-white/10 text-lg font-bold rounded-2xl hover:bg-white/10 transition-all flex items-center justify-center gap-2">
                Browse Competitions
              </Link>
            </motion.div>
          </div>
        </section>

        {/* TRENDING COMPETITIONS SECTION */}
        <section className="w-full max-w-7xl mx-auto px-6 py-12 relative z-10">
          <motion.div 
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.8 }}
          >
            <div className="flex items-center gap-3 mb-8">
              <CircleDashed className="w-5 h-5 text-brand-lime animate-[spin_4s_linear_infinite]" />
              <h2 className="text-2xl md:text-3xl font-black text-white tracking-tight">Trending Competitions</h2>
              <div className="flex-1 h-px bg-gradient-to-r from-white/10 to-transparent ml-4" />
            </div>

            {/* Skeletons ready to be replaced with real LeagueCards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
              <LeagueCardSkeleton />
              <LeagueCardSkeleton />
              <div className="hidden lg:block"><LeagueCardSkeleton /></div>
            </div>
            
            <div className="mt-8 text-center">
              <Link href="/leagues" className="inline-flex items-center gap-2 text-sm font-bold text-brand-lime hover:text-white transition-colors">
                View all active leagues <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </motion.div>
        </section>

        {/* FEATURES SECTION */}
        <section className="w-full max-w-7xl mx-auto px-6 py-20 relative z-10">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <FeatureCard 
              icon={Gamepad2}
              title="Everything In One Hub"
              description="Fixtures, standings, chatrooms, and score management all in a single workspace."
              delay={0.1}
            />
            <FeatureCard 
              icon={Shield}
              title="Build Your Brand"
              description="Grow followers, host premium competitions, and establish trust in the esports community."
              delay={0.2}
            />
            <FeatureCard 
              icon={TrendingUp}
              title="Professional Tracking"
              description="Live standings, knockout brackets, Swiss rounds, and detailed statistics."
              delay={0.3}
            />
          </div>
        </section>

      </main>

      <SimpleFooter />
    </div>
  );
}

function FeatureCard({ icon: Icon, title, description, delay }: { icon: any, title: string, description: string, delay: number }) {
  return (
    <motion.div 
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.5, delay }}
      className="p-8 rounded-3xl bg-[#0F172A] border border-white/5 hover:border-brand-lime/30 transition-colors group"
    >
      <div className="w-14 h-14 bg-brand-lime/10 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
        <Icon className="w-7 h-7 text-brand-lime" />
      </div>
      <h3 className="text-2xl font-black text-white mb-3 tracking-tight">{title}</h3>
      <p className="text-slate-400 font-medium leading-relaxed">{description}</p>
    </motion.div>
  );
}
