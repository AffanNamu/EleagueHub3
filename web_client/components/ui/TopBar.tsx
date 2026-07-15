'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Search, Bell } from 'lucide-react';
import { Glass } from './Glass';

export const TopBar = () => {
  const [query, setQuery] = useState('');
  const router = useRouter();

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      router.push(`/search?q=${encodeURIComponent(query.trim())}`);
    }
  };

  return (
    <div className="w-full mb-6 hidden md:flex items-center justify-between gap-4">
      <div className="flex-1 max-w-xl">
        <form onSubmit={handleSearch} className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input 
            type="text" 
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search leagues, organizers, or players..." 
            className="w-full pl-10 pr-4 py-3 bg-brand-surface border border-white/10 rounded-2xl text-white focus:outline-none focus:border-brand-lime transition-colors shadow-lg"
          />
        </form>
      </div>
      
      <Glass className="p-3 cursor-pointer hover:bg-white/10 transition-colors rounded-2xl">
        <Bell className="w-5 h-5 text-gray-300" />
      </Glass>
    </div>
  );
};
