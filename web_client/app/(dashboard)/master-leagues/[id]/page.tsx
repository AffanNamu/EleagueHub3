'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useMasterLeagueDetails } from '@/hooks/useMasterLeagues';
import { toggleFollowWorkspaceWeb, renameMasterLeagueWeb, deleteMasterLeagueWeb } from '@/lib/masterLeagues/masterLeaguesRepository';
import {
  useMasterLeagueAnnouncements,
  addMasterLeagueAnnouncementWeb,
  pinMasterLeagueAnnouncementWeb,
  unpinMasterLeagueAnnouncementWeb,
  deleteMasterLeagueAnnouncementWeb,
} from '@/lib/masterLeagues/masterLeagueAnnouncementsRepository';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { LeagueAnnouncement } from '@/lib/models/leagueDetails';
import { checkChatAccessWeb, startOrGetThreadWeb, getThreadId } from '@/lib/chat/privateChatRepository';
import { Glass } from '@/components/ui/Glass';
import { LeagueCard } from '@/components/leagues/LeagueCard';
import { Loader2, ArrowLeft, Network as Hub, ShieldCheck, Users, Trophy, ShieldAlert, Plus, Edit2, Link as LinkIcon, Trash2, Megaphone, Pin, PinOff, X, MessageSquare } from 'lucide-react';
import Link from 'next/link';

export default function MasterLeagueDashboard() {
  const params = useParams();
  const router = useRouter();
  const mlId = params.id as string;
  const [authUid, setAuthUid] = useState<string | null>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged(u => setAuthUid(u?.uid || null));
    return () => unsub();
  }, []);

  const { masterLeague, childLeagues, loading } = useMasterLeagueDetails(mlId);
  const { announcements } = useMasterLeagueAnnouncements(mlId);

  const [followBusy, setFollowBusy] = useState(false);
  const [isFollowing, setIsFollowing] = useState(false);
  const [messaging, setMessaging] = useState(false);

  const [showAnnModal, setShowAnnModal] = useState(false);
  const [annTitle, setAnnTitle] = useState('');
  const [annMsg, setAnnMsg] = useState('');
  const [posting, setPosting] = useState(false);

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;

  if (!masterLeague) {
    return (
      <div className="text-center py-20 bg-[#0B1221] border border-[#1E293B] rounded-3xl max-w-2xl mx-auto mt-10">
        <ShieldAlert className="w-12 h-12 text-[#1E293B] mx-auto mb-4"/>
        <p className="text-white font-black text-lg">Master League Not Found</p>
        <button onClick={() => router.push('/master-leagues')} className="mt-4 px-6 py-2 bg-[#1E293B] text-white rounded-xl font-bold">Go Back</button>
      </div>
    );
  }

  const isOwner = authUid === masterLeague.ownerId;

  const handleMessage = async () => {
    // Mirrors organizer_profile_screen.dart's PrivateMessageButton, which
    // targets the workspace owner (ml.ownerId) — a visitor can message the
    // organizer directly from this page, gated the same way as any other
    // private chat (blocked/Premium-required), same as ProfileDetailView's.
    if (!authUid || messaging) return;
    setMessaging(true);
    try {
      const access = await checkChatAccessWeb(authUid, masterLeague.ownerId);
      if (access === 'blocked') {
        alert('You cannot message this organizer.');
        return;
      }
      if (access === 'locked') {
        alert('Starting a private chat requires Premium. This organizer can still message you first.');
        return;
      }
      const threadId = access === 'threadExists'
        ? getThreadId(authUid, masterLeague.ownerId)
        : (await startOrGetThreadWeb(authUid, masterLeague.ownerId)).id;
      router.push(`/messages/${threadId}`);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Could not start conversation.');
    } finally {
      setMessaging(false);
    }
  };

  const handleToggleFollow = async () => {
    if (!authUid) return;
    setFollowBusy(true);
    try {
      await toggleFollowWorkspaceWeb(mlId, authUid, isFollowing);
      setIsFollowing(!isFollowing);
    } catch (err) {
      alert("Failed to update follow status.");
    } finally {
      setFollowBusy(false);
    }
  };

  const handleRename = async () => {
    const newName = prompt('Enter new Master League name:', masterLeague.name);
    if (newName && newName.trim() && newName !== masterLeague.name) {
      await renameMasterLeagueWeb(mlId, newName);
    }
  };

  const handleDelete = async () => {
    const confirmText = prompt(`Type DELETE to permanently destroy ${masterLeague.name}`);
    if (confirmText === 'DELETE') {
      await deleteMasterLeagueWeb(mlId);
      router.push('/master-leagues');
    }
  };

  const handlePostAnnouncement = async () => {
    if (!authUid || !annTitle.trim() || !annMsg.trim()) {
      alert('Please enter both title and message.');
      return;
    }
    setPosting(true);
    try {
      const profile = await fetchUserProfileByUserId(authUid);
      const authorName = profile?.teamName.trim() || 'Organizer';
      await addMasterLeagueAnnouncementWeb({
        masterLeagueId: mlId,
        title: annTitle,
        message: annMsg,
        authorId: authUid,
        authorName,
      });
      setAnnTitle('');
      setAnnMsg('');
      setShowAnnModal(false);
    } catch (err) {
      alert('Failed to post announcement.');
    } finally {
      setPosting(false);
    }
  };

  const handlePin = async (ann: LeagueAnnouncement) => {
    try {
      await pinMasterLeagueAnnouncementWeb({ masterLeagueId: mlId, announcementId: ann.id, pinnedBy: authUid || '' });
    } catch {
      alert('Failed to pin announcement.');
    }
  };

  const handleUnpin = async (ann: LeagueAnnouncement) => {
    try {
      await unpinMasterLeagueAnnouncementWeb({ masterLeagueId: mlId, announcementId: ann.id });
    } catch {
      alert('Failed to unpin announcement.');
    }
  };

  const handleDeleteAnnouncement = async (ann: LeagueAnnouncement) => {
    if (!confirm('Delete this announcement?')) return;
    try {
      await deleteMasterLeagueAnnouncementWeb({ masterLeagueId: mlId, announcementId: ann.id });
    } catch {
      alert('Failed to delete announcement.');
    }
  };

  return (
    <div className="max-w-6xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      
      <div className="flex items-center gap-4 mt-4 mb-2">
        <button onClick={() => router.push('/master-leagues')} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white"/>
        </button>
        <h1 className="text-xl font-black text-white">Master League Dashboard</h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* ── LEFT COLUMN (HERO & STATS) ── */}
        <div className="lg:col-span-2 space-y-6">
          
          <Glass className="p-0 overflow-hidden border border-[#1E293B] bg-[#0B1221] rounded-3xl">
            <div className="relative h-48 bg-slate-900">
              {masterLeague.bannerUrl ? (
                <img src={masterLeague.bannerUrl} className="w-full h-full object-cover opacity-80" alt="Banner" />
              ) : (
                <div className="absolute inset-0 bg-gradient-to-br from-[#1E293B] to-[#070B14]" />
              )}
            </div>
            
            <div className="px-6 pb-8 relative">
              <div className="absolute -top-12 left-6 w-24 h-24 rounded-full border-4 border-[#0B1221] bg-[#1E293B] overflow-hidden shadow-2xl flex items-center justify-center">
                {masterLeague.logoUrl ? <img src={masterLeague.logoUrl} className="w-full h-full object-cover" /> : <Hub className="w-10 h-10 text-gray-500"/>}
              </div>
              
              <div className="pl-32 pt-3 flex items-start justify-between">
                <div>
                  <h1 className="text-2xl font-black text-white flex items-center gap-2">
                    {masterLeague.name}
                    {masterLeague.verifiedBadge && <ShieldCheck className="w-5 h-5 text-sky-400"/>}
                  </h1>
                  <span className="inline-block mt-1 px-3 py-1 bg-[#BEF264]/10 text-[#BEF264] border border-[#BEF264]/20 rounded-lg text-xs font-black uppercase tracking-widest">
                    {masterLeague.plan} Plan
                  </span>
                </div>
              </div>

              <p className="text-gray-400 text-sm font-medium leading-relaxed mt-8 max-w-xl">
                {masterLeague.bio || "No organizer bio provided yet."}
              </p>
            </div>
          </Glass>

          {/* Stats Grid */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <StatCard bg="bg-[#BEF264]/10" border="border-[#BEF264]/20" icon={Trophy} label="Competitions" tint="text-[#BEF264]" value={childLeagues.length}/>
            <StatCard bg="bg-red-500/10" border="border-red-500/20" icon={Users} label="Followers" tint="text-red-500" value={masterLeague.followersCount || 0}/>
            <StatCard bg="bg-sky-400/10" border="border-sky-400/20" icon={ShieldCheck} label="Status" tint="text-sky-400" value={masterLeague.verifiedBadge ? 'Verified' : 'Public'}/>
            <StatCard bg="bg-purple-400/10" border="border-purple-400/20" icon={Hub} label="Matches" tint="text-purple-400" value={masterLeague.totalMatches || 0}/>
          </div>

          {/* Organizer Announcements */}
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-lg font-black text-white flex items-center gap-2">
                <Megaphone className="w-5 h-5 text-[#BEF264]"/> Organizer Announcements
              </h2>
              {isOwner && (
                <button onClick={() => setShowAnnModal(true)} className="px-3 py-2 bg-[#BEF264]/10 border border-[#BEF264]/20 text-[#BEF264] text-xs font-black rounded-xl hover:bg-[#BEF264]/20 transition-colors">
                  Post Announcement
                </button>
              )}
            </div>

            {announcements.length === 0 ? (
              <div className="p-8 text-center border border-[#1E293B] bg-[#070B14] rounded-2xl">
                <p className="text-gray-500 font-bold text-sm">No announcements posted yet.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {[...announcements].sort((a, b) => (a.pinned === b.pinned ? 0 : a.pinned ? -1 : 1)).map((ann) => {
                  const canManage = isOwner || ann.authorId === authUid;
                  return (
                    <div key={ann.id} className={`p-4 rounded-2xl border ${ann.pinned ? 'bg-[#BEF264]/5 border-[#BEF264]/30' : 'bg-[#070B14] border-[#1E293B]'}`}>
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            {ann.pinned && <Pin className="w-3.5 h-3.5 text-[#BEF264] shrink-0" />}
                            <h3 className="text-sm font-black text-white truncate">{ann.title}</h3>
                          </div>
                          <p className="text-xs font-semibold text-gray-400 mt-1.5 leading-relaxed whitespace-pre-wrap">{ann.message}</p>
                          <p className="text-[10px] font-bold text-gray-600 mt-2 uppercase tracking-widest">
                            {ann.authorName || 'Organizer'} • {new Date(ann.createdAtMs).toLocaleString()}
                          </p>
                        </div>
                        {(isOwner || canManage) && (
                          <div className="flex items-center gap-1 shrink-0">
                            {isOwner && (
                              ann.pinned ? (
                                <button onClick={() => handleUnpin(ann)} title="Unpin" className="p-2 text-gray-400 hover:text-white hover:bg-white/10 rounded-lg transition-colors">
                                  <PinOff className="w-4 h-4" />
                                </button>
                              ) : (
                                <button onClick={() => handlePin(ann)} title="Pin" className="p-2 text-gray-400 hover:text-[#BEF264] hover:bg-[#BEF264]/10 rounded-lg transition-colors">
                                  <Pin className="w-4 h-4" />
                                </button>
                              )
                            )}
                            {canManage && (
                              <button onClick={() => handleDeleteAnnouncement(ann)} title="Delete" className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-500/10 rounded-lg transition-colors">
                                <Trash2 className="w-4 h-4" />
                              </button>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Child Competitions */}
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-lg font-black text-white flex items-center gap-2">
                <Trophy className="w-5 h-5 text-[#BEF264]"/> Competitions
              </h2>
            </div>

            {childLeagues.length === 0 ? (
              <div className="p-8 text-center border border-[#1E293B] bg-[#070B14] rounded-2xl">
                <p className="text-gray-500 font-bold text-sm">No competitions active in this workspace.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {childLeagues.map(l => (
                  <div key={l.id} className="h-[236px]">
                     <LeagueCard league={l} onOpen={() => router.push(`/leagues/${l.id}`)}/>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* ── RIGHT COLUMN (ACTIONS) ── */}
        <div className="space-y-6">
          {isOwner ? (
            <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
              <h2 className="text-sm font-black text-white uppercase tracking-widest mb-4">Owner Actions</h2>
              <div className="space-y-3">
                <ActionBtn desc="New league inside this workspace" icon={Plus} label="Create Competition" onClick={() => router.push(`/leagues/create?masterLeagueId=${mlId}`)} tint="text-[#BEF264]"/>
                <ActionBtn desc="Update name" icon={Edit2} label="Rename Workspace" onClick={handleRename} tint="text-[#BEF264]"/>
                <ActionBtn desc="Manage users" icon={ShieldAlert} label="Discipline" onClick={() => alert('Discipline panel coming soon')} tint="text-red-500" />
                <ActionBtn bg="bg-red-500/10" border="border-red-500/30" desc="Permanent action" icon={Trash2} label="Delete Workspace" onClick={handleDelete} tint="text-red-500"/>
              </div>
            </div>
          ) : (
            <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
              <h2 className="text-sm font-black text-white uppercase tracking-widest mb-4">Interact</h2>
              <div className="space-y-3">
                <button
                  onClick={handleToggleFollow} disabled={followBusy}
                  className={`w-full py-3.5 rounded-xl font-black text-sm flex items-center justify-center gap-2 transition-all ${isFollowing ? 'bg-white/10 text-white hover:bg-white/20' : 'bg-[#BEF264] text-[#0F172A] hover:brightness-110'}`}
                >
                  {followBusy ? <Loader2 className="w-4 h-4 animate-spin"/> : (isFollowing ? <>Following</> : <><Plus className="w-4 h-4"/> Follow Organizer</>)}
                </button>
                <button
                  onClick={handleMessage} disabled={messaging}
                  className="w-full py-3.5 rounded-xl font-black text-sm flex items-center justify-center gap-2 bg-white/10 text-white hover:bg-white/20 disabled:opacity-50 transition-all"
                >
                  {messaging ? <Loader2 className="w-4 h-4 animate-spin"/> : <><MessageSquare className="w-4 h-4"/> Message Organizer</>}
                </button>
              </div>
            </div>
          )}

          {/* Social Links Read-Only */}
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-sm font-black text-white uppercase tracking-widest mb-4">Official Links</h2>
            {Object.keys(masterLeague.socialLinks || {}).length === 0 ? (
              <p className="text-xs font-semibold text-gray-500">No official links published.</p>
            ) : (
              <div className="space-y-3">
                {Object.entries(masterLeague.socialLinks || {}).map(([platform, url]) => (
                  <a key={platform} href={url as string} target="_blank" rel="noreferrer" className="flex items-center gap-3 p-3 bg-[#070B14] rounded-xl border border-white/5 hover:border-white/20 transition-colors">
                    <LinkIcon className="w-4 h-4 text-gray-400"/>
                    <span className="text-sm font-bold text-white capitalize">{platform}</span>
                  </a>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Post Announcement Modal */}
      {showAnnModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-lg bg-[#0F172A] border border-[#1E293B] rounded-3xl p-6 shadow-2xl relative">
            <button onClick={() => setShowAnnModal(false)} className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-[#1E293B] text-gray-400 hover:text-white transition-colors">
              <X className="w-4 h-4" />
            </button>
            <h2 className="text-xl font-black text-white mb-1">Post Organizer Announcement</h2>
            <p className="text-xs font-semibold text-gray-400 mb-6">Visible to everyone who follows this workspace.</p>
            <div className="space-y-4 mb-6">
              <input
                type="text" placeholder="Title" value={annTitle} onChange={(e) => setAnnTitle(e.target.value)}
                className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-bold text-white outline-none focus:border-[#BEF264]"
              />
              <textarea
                placeholder="Message" value={annMsg} onChange={(e) => setAnnMsg(e.target.value)} rows={4}
                className="w-full p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm font-medium text-white outline-none focus:border-[#BEF264] resize-none"
              />
            </div>
            <button onClick={handlePostAnnouncement} disabled={posting || !annTitle.trim() || !annMsg.trim()} className="w-full py-3.5 rounded-xl bg-[#BEF264] text-[#0F172A] font-black hover:brightness-110 disabled:opacity-50 shadow-lg shadow-[#BEF264]/10">
              {posting ? 'Posting...' : 'Post Announcement'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function StatCard({ icon: Icon, label, value, tint, bg, border }: any) {
  return (
    <div className={`p-4 rounded-2xl border bg-[#0B1221] ${border} shadow-lg flex flex-col justify-center items-start`}>
      <div className={`w-8 h-8 rounded-full ${bg} flex items-center justify-center mb-2`}>
        <Icon className={`w-4 h-4 ${tint}`}/>
      </div>
      <span className="text-xl font-black text-white tabular-nums">{value}</span>
      <span className="text-[10px] font-black uppercase tracking-widest text-gray-500 mt-0.5">{label}</span>
    </div>
  );
}

function ActionBtn({ icon: Icon, label, desc, onClick, tint, bg, border }: any) {
  return (
    <button onClick={onClick} className={`w-full flex items-center gap-4 p-3.5 ${bg || 'bg-[#070B14]'} border ${border || 'border-[#1E293B]'} rounded-2xl hover:bg-white/5 transition-colors text-left group`}>
      <div className={`w-10 h-10 rounded-xl ${bg || 'bg-white/5'} flex items-center justify-center shrink-0 ${tint}`}>
        <Icon className="w-5 h-5"/>
      </div>
      <div>
        <h3 className={`text-sm font-black transition-colors ${tint === 'text-red-500' ? 'text-red-400' : 'text-white group-hover:text-white'}`}>{label}</h3>
        <p className="text-[10px] font-bold text-gray-500 uppercase tracking-widest mt-0.5">{desc}</p>
      </div>
    </button>
  );
}
