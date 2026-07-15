'use client';

import { useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useLeagues } from '@/hooks/useLeagues';
import { Glass } from '@/components/ui/Glass';
import { Loader2, User, Trophy, ShieldCheck, Mail, ShieldAlert, ArrowRight } from 'lucide-react';
import Link from 'next/link';

export default function ProfileScreen() {
  const router = useRouter();
  const { leagues, loading } = useLeagues();
  const user = auth.currentUser;

  const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  const isSuperAdmin = user?.uid === SUPER_ADMIN_UID;

  // Split leagues just like profile_screen.dart
  const { myTournaments, myMemberships } = useMemo(() => {
    const uid = user?.uid;
    if (!uid) return { myTournaments: [], myMemberships: [] };

    return {
      myTournaments: leagues.filter(l => l.organizerId === uid),
      myMemberships: leagues.filter(l => l.memberIds?.includes(uid) && l.organizerId !== uid)
    };
  }, [leagues, user]);

  if (!user) return null;

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
          <User className="w-6 h-6 text-[#38BDF8]" /> My Profile
        </h1>
        <p className="text-gray-400 mt-1">Manage your identity and memberships.</p>
      </div>

      {/* Identity Card */}
      <Glass className="p-6 md:p-8 flex items-center gap-6">
        <div className="w-20 h-20 bg-brand-surface border-2 border-[#38BDF8]/30 rounded-full overflow-hidden shrink-0">
          {user.photoURL ? (
            <img src={user.photoURL} alt="Profile" className="w-full h-full object-cover" />
          ) : (
            <User className="w-10 h-10 m-auto text-gray-500 mt-5" />
          )}
        </div>
        <div className="flex-1">
          <h2 className="text-2xl font-black text-white">{user.displayName || 'eSports Player'}</h2>
          <div className="flex items-center gap-2 text-gray-400 mt-1 text-sm">
            <Mail className="w-4 h-4" /> {user.email}
          </div>
        </div>
      </Glass>

      {/* Super Admin Quick Links */}
      {isSuperAdmin && (
        <Glass className="p-0 overflow-hidden border-brand-red/30">
          <div className="bg-brand-red/10 p-4 flex items-center gap-2 border-b border-brand-red/20">
            <ShieldAlert className="w-5 h-5 text-brand-red" />
            <h3 className="font-bold text-brand-red">Super Admin Controls</h3>
          </div>
          <div className="p-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Link href="/admin/global-chat-requests" className="flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/5 border border-white/5">
              <span className="font-bold text-gray-300">Global Chat Requests</span>
              <ArrowRight className="w-4 h-4 text-gray-500" />
            </Link>
            <div className="flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/5 border border-white/5 opacity-50 cursor-not-allowed">
              <span className="font-bold text-gray-300">App Config (Mobile Only)</span>
            </div>
          </div>
        </Glass>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* My Tournaments (Organizer) */}
        <Glass className="p-6 flex flex-col h-full">
          <div className="flex items-center gap-2 mb-4">
            <ShieldCheck className="w-5 h-5 text-brand-lime" />
            <h3 className="font-bold text-white text-lg">My Tournaments</h3>
          </div>
          {loading ? (
            <div className="flex justify-center py-6"><Loader2 className="w-6 h-6 animate-spin text-brand-lime" /></div>
          ) : myTournaments.length === 0 ? (
            <p className="text-gray-500 text-sm flex-1">You haven't organized any leagues yet.</p>
          ) : (
            <div className="space-y-3 flex-1">
              {myTournaments.map(l => (
                <Link key={l.id} href={`/leagues/${l.id}`} className="flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/5 border border-white/5 transition-colors">
                  <span className="font-bold text-gray-200 line-clamp-1">{l.name}</span>
                  <span className="text-xs bg-brand-lime/10 text-brand-lime px-2 py-1 rounded font-bold uppercase">Owner</span>
                </Link>
              ))}
            </div>
          )}
        </Glass>

        {/* My Memberships (Participant) */}
        <Glass className="p-6 flex flex-col h-full">
          <div className="flex items-center gap-2 mb-4">
            <Trophy className="w-5 h-5 text-[#38BDF8]" />
            <h3 className="font-bold text-white text-lg">My Memberships</h3>
          </div>
          {loading ? (
            <div className="flex justify-center py-6"><Loader2 className="w-6 h-6 animate-spin text-[#38BDF8]" /></div>
          ) : myMemberships.length === 0 ? (
            <p className="text-gray-500 text-sm flex-1">You haven't joined any leagues yet.</p>
          ) : (
            <div className="space-y-3 flex-1">
              {myMemberships.map(l => (
                <Link key={l.id} href={`/leagues/${l.id}`} className="flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/5 border border-white/5 transition-colors">
                  <span className="font-bold text-gray-200 line-clamp-1">{l.name}</span>
                  <span className="text-xs bg-[#38BDF8]/10 text-[#38BDF8] px-2 py-1 rounded font-bold uppercase">Member</span>
                </Link>
              ))}
            </div>
          )}
        </Glass>
      </div>
    </div>
  );
}
