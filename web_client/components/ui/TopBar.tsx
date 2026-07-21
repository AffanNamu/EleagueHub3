'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Search, Bell, MessageSquare, ShieldCheck } from 'lucide-react';
import { auth, db } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';

export const TopBar = () => {
  const [query, setQuery] = useState('');
  const router = useRouter();
  
  // State for the profile picture, name, and verification badge from Firestore
  const [userProfile, setUserProfile] = useState<{ displayName: string | null; photoURL: string | null; isVerified: boolean } | null>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      if (currentUser) {
        let displayName = currentUser.displayName;
        let photoURL = currentUser.photoURL;
        let isVerified = false;

        // Fetch the absolute latest data from the Firestore users collection
        try {
          const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
          if (userDoc.exists()) {
            const data = userDoc.data();
            displayName = data.displayName || displayName;
            // Handle both photoUrl and photoURL naming conventions
            photoURL = data.photoUrl || data.photoURL || photoURL;
            isVerified = data.isVerifiedOrganizer || data.verifiedBadge || false;
          }
        } catch (err) {
          console.error("Error fetching user profile for TopBar", err);
        }

        setUserProfile({ displayName, photoURL, isVerified });
      } else {
        setUserProfile(null);
      }
    });
    return () => unsubscribe();
  }, []);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      router.push(`/search?q=${encodeURIComponent(query.trim())}`);
    }
  };

  return (
    <div className="w-full mb-6 hidden md:flex items-center justify-between gap-4 py-2">
      
      {/* Search Bar - Inner Glass View */}
      <div className="flex-1 max-w-xl">
        <form onSubmit={handleSearch} className="relative group">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-500 w-5 h-5 group-focus-within:text-brand-lime transition-colors" />
          <input 
            type="text" 
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search competitions, teams, organizers..." 
            className="w-full pl-12 pr-4 py-2.5 bg-white/5 border border-white/10 rounded-xl text-white text-sm focus:outline-none focus:border-brand-lime focus:bg-white/10 transition-all shadow-inner"
          />
        </form>
      </div>
      
      {/* Right Side Icons & Profile */}
      <div className="flex items-center gap-4">
        
        {/* Top Nav Links */}
        <div className="hidden lg:flex items-center gap-6 mr-4 text-sm font-bold text-gray-400">
          <button onClick={() => router.push('/master-leagues/discovery')} className="hover:text-white transition-colors">Explore</button>
          <button onClick={() => router.push('/leagues')} className="hover:text-white transition-colors">Competitions</button>
          <button onClick={() => router.push('/rankings')} className="hover:text-white transition-colors">Rankings</button>
        </div>

        {/* Icons */}
        <div className="flex items-center gap-3">
          <button className="relative p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:bg-[#1E293B] transition-colors text-gray-400 hover:text-white">
            <Bell className="w-5 h-5" />
            <span className="absolute -top-1 -right-1 w-4 h-4 bg-brand-lime text-brand-navy text-[10px] font-black flex items-center justify-center rounded-full">
              3
            </span>
          </button>
          
          <button onClick={() => router.push('/global-chat')} className="relative p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:bg-[#1E293B] transition-colors text-gray-400 hover:text-white">
            <MessageSquare className="w-5 h-5" />
            <span className="absolute -top-1 -right-1 w-4 h-4 bg-brand-lime text-brand-navy text-[10px] font-black flex items-center justify-center rounded-full">
              5
            </span>
          </button>
        </div>

        {/* Profile Pic & Name */}
        <div onClick={() => router.push('/profile')} className="flex items-center gap-3 pl-4 border-l border-[#1E293B] cursor-pointer hover:opacity-80 transition-opacity">
          <div className="flex flex-col items-end hidden xl:flex">
            <span className="text-sm font-bold text-white flex items-center gap-1">
              {userProfile?.displayName || 'User'}
              {userProfile?.isVerified && <ShieldCheck className="w-4 h-4 text-brand-lime" />}
            </span>
            <span className="text-[10px] text-gray-400">Organizer</span>
          </div>
          
          <div className="w-10 h-10 rounded-full bg-[#1E293B] border-2 border-[#1E293B] hover:border-brand-lime transition-colors overflow-hidden shrink-0 flex items-center justify-center shadow-lg">
            {userProfile?.photoURL ? (
              <img src={userProfile.photoURL} alt="Profile" className="w-full h-full object-cover" />
            ) : (
              <span className="text-white font-bold text-sm">
                {userProfile?.displayName?.charAt(0).toUpperCase() || 'U'}
              </span>
            )}
          </div>
        </div>

      </div>
    </div>
  );
};
