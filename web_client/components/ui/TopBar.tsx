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
  
  // State maps directly to Flutter's UserProfile model
  const [userProfile, setUserProfile] = useState<{ 
    displayName: string; 
    photoURL: string | null; 
    isVerified: boolean;
  } | null>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      if (currentUser) {
        // Defaults from Auth
        let displayName = currentUser.displayName || 'User';
        let photoURL = currentUser.photoURL;
        let isVerified = false;

        try {
          const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
          if (userDoc.exists()) {
            const data = userDoc.data();
            
            // Match Flutter UserProfile display name logic (teamName -> username -> shareId)
            const teamName = data.teamName?.trim();
            const usernameDisplay = data.username?.trim();
            
            if (teamName) {
              displayName = teamName;
            } else if (usernameDisplay) {
              displayName = `@${usernameDisplay}`;
            }

            // Match Flutter UserProfile effectivePhotoUrl logic
            photoURL = data.profileImageUrl?.trim() || data.teamImageUrl?.trim() || data.photoUrl?.trim() || photoURL;
            
            // Match Flutter UserProfile verified logic
            isVerified = data.isVerified === true || data.verifiedBadge === true || (data.verificationStatus?.trim().toLowerCase() === 'approved');
          }
        } catch (err) {
          console.error("[TopBar] Error fetching user profile:", err);
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
    <div className="w-full mb-6 hidden md:flex items-center justify-between gap-4 py-2 px-4 md:px-6 lg:px-8 mt-4">
      
      {/* Search Bar */}
      <div className="flex-1 max-w-xl">
        <form onSubmit={handleSearch} className="relative group">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-500 w-5 h-5 group-focus-within:text-[#BEF264] transition-colors" />
          <input 
            type="text" 
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search competitions, teams, organizers..." 
            className="w-full pl-12 pr-4 py-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-white text-sm focus:outline-none focus:border-[#BEF264] transition-all shadow-inner"
          />
        </form>
      </div>
      
      {/* Right Side Icons & Profile */}
      <div className="flex items-center gap-4">
        
        {/* Top Nav Quick Links */}
        <div className="hidden lg:flex items-center gap-6 mr-4 text-sm font-bold text-gray-400">
          <button onClick={() => router.push('/organizer-discovery')} className="hover:text-white transition-colors">Organizers</button>
          <button onClick={() => router.push('/discovery/feed')} className="hover:text-white transition-colors">Public Feed</button>
        </div>

        {/* Action Icons (Mock data removed) */}
        <div className="flex items-center gap-3">
          <button className="relative p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:bg-[#1E293B] transition-colors text-gray-400 hover:text-white">
            <Bell className="w-5 h-5" />
          </button>
          
          <button onClick={() => router.push('/messages')} className="relative p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:bg-[#1E293B] transition-colors text-gray-400 hover:text-white">
            <MessageSquare className="w-5 h-5" />
          </button>
        </div>

        {/* Profile User Pill */}
        <div onClick={() => router.push('/profile')} className="flex items-center gap-3 pl-4 border-l border-[#1E293B] cursor-pointer hover:opacity-80 transition-opacity">
          <div className="flex flex-col items-end hidden xl:flex">
            <span className="text-sm font-bold text-white flex items-center gap-1">
              {userProfile?.displayName || 'Loading...'}
              {userProfile?.isVerified && <ShieldCheck className="w-4 h-4 text-[#BEF264]" />}
            </span>
          </div>
          
          <div className="w-10 h-10 rounded-full bg-[#1E293B] border-2 border-[#1E293B] hover:border-[#BEF264] transition-colors overflow-hidden shrink-0 flex items-center justify-center shadow-lg">
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
