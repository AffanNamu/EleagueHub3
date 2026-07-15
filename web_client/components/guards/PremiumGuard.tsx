'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Loader2, Lock } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';
import Link from 'next/link';

export const PremiumGuard = ({ children }: { children: React.ReactNode }) => {
  const [isPremium, setIsPremium] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const checkPremiumStatus = async () => {
      if (!auth.currentUser) return;
      try {
        const userDoc = await getDoc(doc(db, 'users', auth.currentUser.uid));
        if (userDoc.exists()) {
          setIsPremium(userDoc.data().isPremium === true);
        } else {
          setIsPremium(false);
        }
      } catch (error) {
        console.error("Error checking premium status", error);
        setIsPremium(false);
      } finally {
        setLoading(false);
      }
    };

    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (user) {
        checkPremiumStatus();
      } else {
        setLoading(false);
      }
    });

    return () => unsubscribe();
  }, []);

  if (loading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  if (!isPremium) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] p-4">
        <Glass className="max-w-md p-8 text-center flex flex-col items-center">
          <div className="w-16 h-16 bg-amber-500/20 rounded-full flex items-center justify-center mb-4">
            <Lock className="w-8 h-8 text-amber-500" />
          </div>
          <h2 className="text-2xl font-bold text-white mb-2">Premium Feature</h2>
          <p className="text-gray-400 mb-6">
            This feature is restricted to Elite Organizers and Premium Users. Upgrade your workspace to unlock advanced analytics and tools.
          </p>
          <Link 
            href="/premium" 
            className="w-full py-3 px-4 bg-brand-lime text-brand-navy font-bold rounded-xl hover:bg-brand-lime/90 transition-colors"
          >
            Upgrade to Premium
          </Link>
        </Glass>
      </div>
    );
  }

  return <>{children}</>;
};
