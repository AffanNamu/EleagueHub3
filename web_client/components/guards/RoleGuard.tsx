'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Loader2, ShieldAlert } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';

interface RoleGuardProps {
  leagueId: string;
  allowedRoles: ('admin' | 'owner' | 'moderator')[];
  children: React.ReactNode;
}

export const RoleGuard: React.FC<RoleGuardProps> = ({ leagueId, allowedRoles, children }) => {
  const [hasAccess, setHasAccess] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const checkRole = async () => {
      if (!auth.currentUser || !leagueId) return;
      try {
        // Fetch the user's specific role in this league
        const memberDoc = await getDoc(doc(db, 'leagues', leagueId, 'members', auth.currentUser.uid));
        
        if (memberDoc.exists()) {
          const userRole = memberDoc.data().role;
          setHasAccess(allowedRoles.includes(userRole));
        } else {
          setHasAccess(false); // Not a member
        }
      } catch (error) {
        console.error("Error checking role", error);
        setHasAccess(false);
      } finally {
        setLoading(false);
      }
    };

    checkRole();
  }, [leagueId, allowedRoles]);

  if (loading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  if (!hasAccess) {
    return (
      <div className="flex flex-col items-center justify-center py-20 p-4">
        <Glass className="max-w-md p-8 text-center flex flex-col items-center border-l-4 border-l-brand-red">
          <ShieldAlert className="w-12 h-12 text-brand-red mb-4" />
          <h2 className="text-xl font-bold text-white mb-2">Access Denied</h2>
          <p className="text-gray-400 mb-6">
            You do not have the required permissions ({allowedRoles.join(', ')}) to view this page.
          </p>
          <button 
            onClick={() => router.back()}
            className="px-6 py-2 bg-brand-surface hover:bg-white/10 text-white rounded-xl transition-colors border border-white/10"
          >
            Go Back
          </button>
        </Glass>
      </div>
    );
  }

  return <>{children}</>;
};
