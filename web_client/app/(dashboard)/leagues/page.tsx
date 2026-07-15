'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDocs, collection, query, where, updateDoc, arrayUnion, setDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { useLeagues } from '@/hooks/useLeagues';
import { useEntitlements } from '@/hooks/useEntitlements';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Search, Trophy, Network, Plus, Key, Eye, Users, ShieldAlert } from 'lucide-react';
import Link from 'next/link';

export default function LeaguesScreen() {
  const router = useRouter();
  const { leagues, loading: leaguesLoading, error } = useLeagues();
  const { activePlan, loading: planLoading } = useEntitlements();

  // Mirrors mobile state
  const [activeTab, setActiveTab] = useState<'normal' | 'master'>('normal');
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  
  // Join Modal State
  const [showJoinModal, setShowJoinModal] = useState(false);
  const [joinCode, setJoinCode] = useState('');
  const [joinMode, setJoinMode] = useState<'participant' | 'viewer'>('participant');
  const [joining, setJoining] = useState(false);

  const FREE_LEAGUE_LIMIT = 3;
  
  // Calculate total created to enforce limits
  const createdLeaguesCount = leagues.filter(l => l.organizerId === auth.currentUser?.uid).length;
  const isFreeLimitReached = activePlan === 'basic' && createdLeaguesCount >= FREE_LEAGUE_LIMIT;

  const handleJoinSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!joinCode.trim() || !auth.currentUser) return;
    setJoining(true);

    try {
      const code = joinCode.trim().toUpperCase();
      const q = query(collection(db, 'leagues'), where('id', '==', code)); // Using ID as code fallback for now
      const snap = await getDocs(q);

      if (snap.empty) throw new Error("No league found with that code.");
      const leagueDoc = snap.docs[0];
      const leagueId = leagueDoc.id;
      const uid = auth.currentUser.uid;

      // 1. Add to memberIds
      await updateDoc(doc(db, 'leagues', leagueId), {
        memberIds: arrayUnion(uid)
      });

      // 2. Set membership document based on role
      if (joinMode === 'participant') {
        const memRef = doc(db, 'leagues', leagueId, 'memberships', uid);
        await setDoc(memRef, {
          userId: uid,
          role: 'participant',
          joinedAt: Date.now()
        }, { merge: true });
      } else {
        const memRef = doc(db, 'leagues', leagueId, 'memberships', uid);
        await setDoc(memRef, {
          userId: uid,
          role: 'viewer',
          joinedAt: Date.now()
        }, { merge: true });
      }

      alert(`Successfully joined as ${joinMode}!`);
      setShowJoinModal(false);
      setJoinCode('');
    } catch (err: any) {
      alert(err.message);
    } finally {
      setJoining(false);
    }
  };

  const handleCreateClick = (e: React.MouseEvent) => {
    if (isFreeLimitReached) {
      e.preventDefault();
      alert(`Basic users can create up to ${FREE_LEAGUE_LIMIT} total competitions. Please upgrade your plan to create more.`);
    }
  };

  // Filter Logic (O(n) just like Dart _filteredLeagues)
  const filteredLeagues = leagues.filter(l => {
    const isMaster = !!(l.masterLeagueId && l.masterLeagueId.trim() !== '');
    if (activeTab === 'normal' && isMaster) return false;
    if (activeTab === 'master' && !isMaster) return false;
    if (categoryFilter && l.footballCategory !== categoryFilter) return false;
    if (searchQuery && !l.name.toLowerCase().includes(searchQuery.toLowerCase())) return false;
    return true;
  });

  if (leaguesLoading || planLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-10">
      
      {/* Top Header & Search */}
      <Glass className="p-4 md:p-6 flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black text-white flex items-center gap-2">
            <Trophy className="w-6 h-6 text-brand-lime" />
            My Leagues
          </h1>
          <p className="text-sm text-gray-400 mt-1">
            {activePlan === 'basic' ? `Free Plan: ${createdLeaguesCount} / ${FREE_LEAGUE_LIMIT} slots used` : 'Pro Plan Active: Unlimited slots'}
          </p>
        </div>
        
        <div className="flex flex-col sm:flex-row gap-3">
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-4 h-4" />
            <input 
              type="text" value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search leagues..." 
              className="w-full pl-9 pr-4 py-2 bg-brand-surface border border-white/10 rounded-xl text-white focus:border-brand-lime text-sm"
            />
          </div>
          <button 
            onClick={() => setShowJoinModal(true)}
            className="flex items-center justify-center gap-2 px-4 py-2 bg-brand-surface border border-brand-lime/30 text-brand-lime font-bold rounded-xl hover:bg-brand-lime/10"
          >
            <Key className="w-4 h-4" /> Join
          </button>
          <Link 
            href="/leagues/create"
            onClick={handleCreateClick}
            className={`flex items-center justify-center gap-2 px-4 py-2 font-bold rounded-xl ${isFreeLimitReached ? 'bg-amber-500 text-black hover:bg-amber-400' : 'bg-brand-lime text-brand-navy hover:bg-brand-lime/90'}`}
          >
            {isFreeLimitReached ? <ShieldAlert className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
            {isFreeLimitReached ? 'Upgrade' : 'Create'}
          </Link>
        </div>
      </Glass>

      {/* Tabs & Filters */}
      <div className="flex flex-col gap-4">
        {/* Tab Switcher (_TopLeagueSwitcher) */}
        <div className="flex bg-brand-surface p-1 rounded-2xl w-fit border border-white/5">
          <button 
            onClick={() => setActiveTab('normal')}
            className={`px-6 py-2 rounded-xl text-sm font-bold transition-colors flex items-center gap-2 ${activeTab === 'normal' ? 'bg-brand-lime text-black' : 'text-gray-400 hover:text-white'}`}
          >
            <Trophy className="w-4 h-4" /> Leagues
          </button>
          <button 
            onClick={() => setActiveTab('master')}
            className={`px-6 py-2 rounded-xl text-sm font-bold transition-colors flex items-center gap-2 ${activeTab === 'master' ? 'bg-[#38BDF8] text-black' : 'text-gray-400 hover:text-white'}`}
          >
            <Network className="w-4 h-4" /> Network Competitions
          </button>
        </div>

        {/* Category Chips (_FilterChip) */}
        <div className="flex overflow-x-auto gap-2 pb-2 scrollbar-hide">
          <button onClick={() => setCategoryFilter(null)} className={`px-4 py-1.5 rounded-full text-xs font-bold whitespace-nowrap border ${!categoryFilter ? 'bg-white/20 border-white text-white' : 'bg-brand-surface border-white/5 text-gray-400'}`}>
            All
          </button>
          <button onClick={() => setCategoryFilter('localFootball')} className={`px-4 py-1.5 rounded-full text-xs font-bold whitespace-nowrap border ${categoryFilter === 'localFootball' ? 'bg-brand-lime/20 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400'}`}>
            Local Football
          </button>
          <button onClick={() => setCategoryFilter('proFootball')} className={`px-4 py-1.5 rounded-full text-xs font-bold whitespace-nowrap border ${categoryFilter === 'proFootball' ? 'bg-brand-lime/20 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400'}`}>
            Pro Football
          </button>
          <button onClick={() => setCategoryFilter('esports')} className={`px-4 py-1.5 rounded-full text-xs font-bold whitespace-nowrap border ${categoryFilter === 'esports' ? 'bg-brand-lime/20 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400'}`}>
            eSports
          </button>
        </div>
      </div>

      {/* League Grid */}
      {filteredLeagues.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center border border-dashed border-white/10">
          <Trophy className="w-12 h-12 text-gray-500 mb-3 opacity-50" />
          <h3 className="text-lg font-bold text-white">No leagues found</h3>
          <p className="text-sm text-gray-400 mt-1">Try clearing your filters or create a new league.</p>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredLeagues.map((league) => (
            <Link href={`/leagues/${league.id}`} key={league.id}>
              <Glass className="overflow-hidden hover:scale-[1.02] transition-transform cursor-pointer group p-0 flex flex-col h-full">
                <div className="h-32 bg-brand-surfaceDark relative shrink-0">
                  {league.coverImageUrl ? (
                    <img src={league.coverImageUrl} alt={league.name} className="w-full h-full object-cover opacity-80 group-hover:opacity-100 transition-opacity" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center bg-gradient-to-br from-brand-navy to-brand-surface">
                      <Trophy className="w-10 h-10 text-brand-lime/30" />
                    </div>
                  )}
                  {/* Badges */}
                  <div className="absolute top-2 right-2 flex flex-col gap-1 items-end">
                    {league.masterLeagueId && (
                      <span className="px-2 py-1 bg-amber-500/20 text-amber-500 rounded text-[9px] font-black uppercase tracking-wider border border-amber-500/40">MASTER</span>
                    )}
                    {league.organizerId === auth.currentUser?.uid && (
                      <span className="px-2 py-1 bg-red-500/20 text-red-500 rounded text-[9px] font-black uppercase tracking-wider border border-red-500/40">OWNER</span>
                    )}
                  </div>
                </div>
                
                <div className="p-4 flex-1 flex flex-col">
                  <h3 className="text-lg font-bold text-white line-clamp-1">{league.name}</h3>
                  <p className="text-xs text-brand-lime uppercase tracking-wider font-bold mb-2">{league.format} • {league.footballCategory || 'Category'}</p>
                  <p className="text-sm text-gray-400 line-clamp-2 flex-1">{league.description}</p>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}

      {/* Join Modal (_showJoinByIdSheet equivalent) */}
      {showJoinModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <Glass className="max-w-md w-full p-6 animate-in fade-in zoom-in-95">
            <div className="flex justify-between items-center mb-6">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-brand-lime/10 rounded-full"><Key className="w-5 h-5 text-brand-lime" /></div>
                <h2 className="text-xl font-black text-white">Join League</h2>
              </div>
              <button onClick={() => setShowJoinModal(false)} className="text-gray-500 hover:text-white">✕</button>
            </div>

            <form onSubmit={handleJoinSubmit} className="space-y-6">
              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Enter Join Code</label>
                <input 
                  type="text" value={joinCode} onChange={(e) => setJoinCode(e.target.value)} required
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime font-mono"
                  placeholder="e.g. L-12345"
                />
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-2">Join As</label>
                <div className="grid grid-cols-2 gap-3">
                  <button type="button" onClick={() => setJoinMode('participant')} className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-colors ${joinMode === 'participant' ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/10 text-gray-400 hover:text-white'}`}>
                    <Users className="w-5 h-5" />
                    <span className="text-xs font-bold">Participant</span>
                  </button>
                  <button type="button" onClick={() => setJoinMode('viewer')} className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-colors ${joinMode === 'viewer' ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/10 text-gray-400 hover:text-white'}`}>
                    <Eye className="w-5 h-5" />
                    <span className="text-xs font-bold">Viewer Only</span>
                  </button>
                </div>
                <p className="text-[10px] text-gray-500 mt-2 text-center">
                  {joinMode === 'participant' ? 'You will be added to the roster and can be assigned a team.' : 'You can view standings and chats, but cannot play.'}
                </p>
              </div>

              <button type="submit" disabled={joining || !joinCode.trim()} className="w-full py-3 bg-brand-lime text-brand-navy font-bold rounded-xl hover:bg-brand-lime/90 flex items-center justify-center gap-2">
                {joining ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Join Tournament'}
              </button>
            </form>
          </Glass>
        </div>
      )}

    </div>
  );
}
