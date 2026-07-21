'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Search, ArrowRight } from 'lucide-react';
import { motion } from 'framer-motion';

export function NotFoundSearch() {
  const [query, setQuery] = useState('');
  const router = useRouter();

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      router.push(`/search?q=${encodeURIComponent(query.trim())}`);
    }
  };

  return (
    <motion.form 
      onSubmit={handleSearch}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.3, duration: 0.5 }}
      className="relative w-full max-w-2xl mx-auto mt-8"
    >
      <div className="relative flex items-center w-full h-16 rounded-full bg-brand-surface border border-white/10 overflow-hidden backdrop-blur-md shadow-[0_8px_32px_rgba(0,0,0,0.2)] focus-within:border-brand-lime/50 focus-within:shadow-[0_0_20px_rgba(182,255,0,0.15)] transition-all">
        <div className="pl-6 pr-3 flex items-center justify-center text-slate-400">
          <Search className="w-5 h-5" />
        </div>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search leagues, organizers, or teams..."
          className="flex-1 h-full bg-transparent text-white placeholder:text-slate-500 text-sm md:text-base outline-none font-medium"
        />
        <button 
          type="submit"
          disabled={!query.trim()}
          className="h-10 w-10 md:w-auto md:px-6 mr-3 bg-brand-lime text-slate-900 rounded-full flex items-center justify-center font-bold text-sm hover:brightness-110 transition-all disabled:opacity-50 disabled:cursor-not-allowed group"
        >
          <span className="hidden md:block mr-2">Search</span>
          <ArrowRight className="w-4 h-4 md:w-4 md:h-4 group-hover:translate-x-1 transition-transform" />
        </button>
      </div>
    </motion.form>
  );
}
