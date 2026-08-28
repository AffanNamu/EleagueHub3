'use client';

import { useEffect, useState, useRef } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { onAuthStateChanged, updateProfile, User as FirebaseUser } from 'firebase/auth';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { updateTeamBannerWeb, updateTeamBioWeb, toggleFollowWeb, toggleBlockWeb, checkRelationshipStatusWeb } from '@/lib/profile/teamProfileRepository';
import { useTeamProfile } from '@/hooks/useTeamProfile';
import { toDisplayUsername } from '@/lib/username';
import { Glass } from '@/components/ui/Glass';
import { SquadPitchView } from '@/components/profile/SquadPitchView';
import { UsernameEditModal } from '@/components/profile/UsernameEditModal';

import { 
  Loader2, User, Trophy, ShieldCheck, Edit2, Camera, AtSign, 
  MessageSquare, UserPlus, UserCheck, MoreVertical, Copy, Link as LinkIcon, Flag, ShieldAlert,
  Settings, LogOut
} from 'lucide-react';
import Link from 'next/link';

export default function ProfileScreen() {
  const router = useRouter();
  const params = useParams();
  
  // If no ID is passed, default to auth user's ID
  const routeId = params.id as string;
  
  const [authUser, setAuthUser] = useState<FirebaseUser | null>(null);
  const [authLoading, setAuthLoading] = useState(true);

  // Profile Target Identity
  const [targetUid, setTargetUid] = useState<string>('');
  const isOwner = authUser?.uid === targetUid;

  const { profile: teamProfile, stats, trophies, recentMatches, loading: profileLoading } = useTeamProfile(targetUid || null);

  // Target Display State
  const [displayName, setDisplayName] = useState('');
  const [photoUrl, setPhotoUrl] = useState('');
  const [badges, setBadges] = useState({ staff: false, organizer: false, green: false });
  const [shareId, setShareId] = useState('');
  const [usernameLower, setUsernameLower] = useState('');
  
  // Interactions
  const [isFollowing, setIsFollowing] = useState(false);
  const [isBlocked, setIsBlocked] = useState(false);
  const [interactionLoading, setInteractionLoading] = useState(false);

  // Edit Modals
  const [usernameEditOpen, setUsernameEditOpen] = useState(false);
  const [showMoreMenu, setShowMoreMenu] = useState(false);
  
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const bannerInputRef = useRef<HTMLInputElement>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [uploadingBanner, setUploadingBanner] = useState(false);

  // Auth Listener
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setAuthUser(user);
      setTargetUid(routeId || user?.uid || '');
      setAuthLoading(false);
    });
    return () => unsubscribe();
  }, [routeId]);

  // Fetch Target Data
  useEffect(() => {
    const fetchUserData = async () => {
      if (!targetUid) return;
      try {
        const userDoc = await getDoc(doc(db, 'users', targetUid));
        if (userDoc.exists()) {
          const data = userDoc.data();
          setDisplayName(data.teamName || data.displayName || 'eSports Player');
          setPhotoUrl(data.teamImageUrl || data.profileImageUrl || data.photoUrl || '');
          
          const v = data.verification || {};
          setBadges({
            staff: v.staffVerified === true,
            organizer: v.organizerVerified === true || data.isVerifiedOrganizer === true,
            green: v.greenVerified === true || data.verifiedBadge === true,
          });

          setShareId(data.shareId || `eS${targetUid.substring(0, 8)}`);
          setUsernameLower(data.usernameLower || '');
        }

        if (authUser && !isOwner) {
          const rel = await checkRelationshipStatusWeb(authUser.uid, targetUid);
          setIsFollowing(rel.following);
          setIsBlocked(rel.blocked);
        }
      } catch (err) {
        console.error("Error fetching user data", err);
      }
    };
    
    if (targetUid) fetchUserData();
  }, [targetUid, authUser, isOwner]);

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !isOwner || !authUser) return;
    if (file.size > 5 * 1024 * 1024) return alert("Image under 5MB required.");

    setUploadingAvatar(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/users' });
      await updateDoc(doc(db, 'users', authUser.uid), {
        photoUrl: secureUrl, profileImageUrl: secureUrl, teamImageUrl: secureUrl, updatedAt: Date.now()
      });
      await updateProfile(authUser, { photoURL: secureUrl });
      setPhotoUrl(secureUrl);
    } catch (error: any) {
      alert(error.message);
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleBannerUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !isOwner || !authUser) return;
    setUploadingBanner(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/banners' });
      await updateTeamBannerWeb(authUser.uid, secureUrl);
    } catch (error: any) {
      alert(error.message);
    } finally {
      setUploadingBanner(false);
    }
  };

  const handleEditName = async () => {
    if (!isOwner || !authUser) return;
    const newName = window.prompt("Enter your new profile/team name:", displayName);
    if (!newName || newName.trim() === '' || newName === displayName) return;
    try {
      await updateDoc(doc(db, 'users', authUser.uid), { teamName: newName.trim(), displayName: newName.trim(), updatedAt: Date.now() });
      await updateProfile(authUser, { displayName: newName.trim() });
      setDisplayName(newName.trim());
    } catch (error) {
      alert("Failed to update name.");
    }
  };

  const handleEditBio = async () => {
    if (!isOwner || !authUser) return;
    const newBio = window.prompt("Enter your bio:", teamProfile?.bio || '');
    if (newBio !== null) {
      await updateTeamBioWeb(authUser.uid, newBio.trim());
    }
  };

  const handleToggleFollow = async () => {
    if (!authUser || interactionLoading) return;
    setInteractionLoading(true);
    try {
      await toggleFollowWeb(authUser.uid, targetUid, isFollowing);
      setIsFollowing(!isFollowing);
    } catch (err) {
      alert("Failed to update follow status");
    } finally {
      setInteractionLoading(false);
    }
  };

  const handleToggleBlock = async () => {
    if (!authUser || interactionLoading) return;
    if (!confirm(isBlocked ? 'Unblock user?' : 'Block this user? They will not be able to message you.')) return;
    setInteractionLoading(true);
    try {
      await toggleBlockWeb(authUser.uid, targetUid, isBlocked);
      setIsBlocked(!isBlocked);
      setShowMoreMenu(false);
    } catch (err) {
      alert("Failed to block user");
    } finally {
      setInteractionLoading(false);
    }
  };

  if (authLoading || profileLoading) {
    return <div className="flex justify-center items-center h-[50vh]"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;
  }

  if (!targetUid) {
    return <div className="text-center py-20 text-gray-500 font-bold">Profile not found.</div>;
  }

  return (
    <div className="max-w-4xl mx-auto pb-20 px-4 sm:px-6">
      
      {/* ── COVER & HEADER ── */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl shadow-2xl overflow-hidden mb-6 relative">
        <div className="relative h-48 md:h-64 bg-slate-900 group">
          {teamProfile?.bannerImageUrl ? (
            <img src={teamProfile.bannerImageUrl} className="w-full h-full object-cover opacity-80" alt="Cover" />
          ) : (
            <div className="absolute inset-0 bg-gradient-to-br from-[#BEF264]/20 to-[#070B14]" />
          )}
          
          {isOwner && (
            <>
              <button onClick={() => bannerInputRef.current?.click()} className="absolute top-4 right-4 p-3 bg-black/50 hover:bg-black/80 rounded-xl backdrop-blur text-white transition-colors border border-white/10 shadow-lg z-10 flex items-center gap-2">
                {uploadingBanner ? <Loader2 className="w-4 h-4 animate-spin"/> : <ImageIcon className="w-4 h-4"/>}
                <span className="text-xs font-bold hidden sm:inline">Edit Cover</span>
              </button>
              <input type="file" ref={bannerInputRef} onChange={handleBannerUpload} accept="image/*" className="hidden" />
            </>
          )}

          <div className="absolute -bottom-12 left-6 md:left-10 flex items-end">
            <div onClick={() => isOwner && !uploadingAvatar && avatarInputRef.current?.click()} className={`relative w-28 h-28 md:w-32 md:h-32 rounded-full border-4 border-[#0B1221] bg-[#1E293B] shadow-2xl overflow-hidden ${isOwner ? 'cursor-pointer group/avatar' : ''}`}>
              {photoUrl ? (
                <img src={photoUrl} className="w-full h-full object-cover transition-opacity group-hover/avatar:opacity-50" alt="Avatar" />
              ) : (
                <User className="w-12 h-12 m-auto text-gray-500 mt-8 group-hover/avatar:opacity-50"/>
              )}
              {isOwner && (
                <div className="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 group-hover/avatar:opacity-100 transition-opacity">
                  {uploadingAvatar ? <Loader2 className="w-6 h-6 text-white animate-spin"/> : <Camera className="w-6 h-6 text-white"/>}
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="pt-16 pb-8 px-6 md:px-10">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <div>
              <h1 className="text-2xl md:text-3xl font-black text-white flex items-center gap-2">
                {displayName}
                {isOwner && <button onClick={handleEditName} className="p-1 text-gray-500 hover:text-[#BEF264] transition-colors"><Edit2 className="w-4 h-4"/></button>}
                {badges.green && <ShieldCheck className="w-5 h-5 text-[#22C55E]"/>}
                {badges.organizer && <ShieldCheck className="w-5 h-5 text-amber-500"/>}
              </h1>
              
              <div className="flex flex-wrap items-center gap-4 mt-2">
                <div className="flex items-center gap-1.5 text-[#BEF264] font-bold text-sm bg-[#BEF264]/10 px-3 py-1 rounded-lg">
                  <AtSign className="w-3.5 h-3.5"/>
                  {usernameLower ? toDisplayUsername(usernameLower) : 'No username'}
                  {isOwner && <button onClick={() => setUsernameEditOpen(true)} className="ml-1 text-[#BEF264]/60 hover:text-[#BEF264]"><Edit2 className="w-3 h-3"/></button>}
                </div>
                <div className="text-gray-500 text-sm font-mono flex items-center gap-2">
                  #{shareId}
                  <button onClick={() => { navigator.clipboard.writeText(shareId); alert('Copied ID'); }} className="p-1 hover:text-white"><Copy className="w-3.5 h-3.5"/></button>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2 relative">
              {!isOwner ? (
                <>
                  <button onClick={handleToggleFollow} disabled={interactionLoading} className={`px-5 py-2.5 rounded-xl font-black text-sm flex items-center gap-2 transition-all ${isFollowing ? 'bg-white/10 text-white hover:bg-white/20' : 'bg-[#BEF264] text-[#0F172A] hover:brightness-110'}`}>
                    {isFollowing ? <><UserCheck className="w-4 h-4"/> Following</> : <><UserPlus className="w-4 h-4"/> Follow</>}
                  </button>
                  <button onClick={() => router.push(`/messages/${targetUid}`)} className="p-2.5 bg-[#1E293B] hover:bg-[#2A3A52] text-white rounded-xl transition-colors">
                    <MessageSquare className="w-5 h-5"/>
                  </button>
                  <button onClick={() => setShowMoreMenu(!showMoreMenu)} className="p-2.5 bg-[#1E293B] hover:bg-[#2A3A52] text-gray-400 hover:text-white rounded-xl transition-colors">
                    <MoreVertical className="w-5 h-5"/>
                  </button>

                  {/* Public More Menu */}
                  {showMoreMenu && (
                    <div className="absolute top-14 right-0 w-48 bg-[#0F172A] border border-white/10 rounded-2xl shadow-2xl py-2 z-20">
                      <button onClick={() => { navigator.clipboard.writeText(window.location.href); alert('Link Copied'); setShowMoreMenu(false); }} className="w-full px-4 py-3 text-left text-sm font-bold text-gray-300 hover:bg-white/5 flex items-center gap-2"><LinkIcon className="w-4 h-4"/> Share Profile</button>
                      <button onClick={handleToggleBlock} className="w-full px-4 py-3 text-left text-sm font-bold text-red-500 hover:bg-white/5 flex items-center gap-2"><ShieldAlert className="w-4 h-4"/> {isBlocked ? 'Unblock User' : 'Block User'}</button>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <button onClick={() => router.push('/settings')} className="p-3 bg-[#1E293B] hover:bg-[#2A3A52] text-white rounded-xl transition-colors"><Settings className="w-5 h-5"/></button>
                  <button onClick={() => auth.signOut().then(()=>router.push('/login'))} className="p-3 bg-red-500/10 hover:bg-red-500/20 text-red-500 rounded-xl transition-colors"><LogOut className="w-5 h-5"/></button>
                </>
              )}
            </div>
          </div>

          <div className="mt-6">
            <p className="text-sm text-gray-400 font-medium leading-relaxed max-w-2xl">
              {teamProfile?.bio || (isOwner ? "No bio added yet. Click edit to tell the community about yourself." : "This user hasn't added a bio yet.")}
            </p>
            {isOwner && <button onClick={handleEditBio} className="text-xs font-bold text-[#BEF264] hover:underline mt-2">Edit Bio</button>}
          </div>
        </div>
      </div>

      {/* ── STATS ROW ── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <StatCard label="Followers" value={stats?.followersCount || 0} />
        <StatCard label="Matches" value={stats?.matchesPlayed || 0} />
        <StatCard label="Win Rate" value={`${(stats?.winPercentage || 0).toFixed(0)}%`} highlight />
        <StatCard label="Trophies" value={stats?.trophies || 0} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* ── SQUAD PREVIEW ── */}
        <div className="lg:col-span-1 space-y-6">
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-black text-white flex items-center gap-2">
                <Users className="w-5 h-5 text-[#38BDF8]"/> Squad
              </h2>
              {isOwner && <button onClick={() => router.push(`/profile/${targetUid}/squad`)} className="text-xs font-bold text-[#38BDF8] hover:underline">Edit</button>}
            </div>
            <div className="relative w-full aspect-[2/3] bg-[#070B14] rounded-2xl border border-white/10 overflow-hidden cursor-pointer group" onClick={() => isOwner ? router.push(`/profile/${targetUid}/squad`) : null}>
               <SquadPitchView gameId={teamProfile?.game || 'local_football'} userId={targetUid} isPreview />
               {isOwner && (
                 <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity backdrop-blur-[2px]">
                   <span className="text-white font-black bg-[#38BDF8] px-4 py-2 rounded-xl">Manage Squad</span>
                 </div>
               )}
            </div>
          </div>
        </div>

        {/* ── TROPHIES & RECENT MATCHES ── */}
        <div className="lg:col-span-2 space-y-6">
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-4 flex items-center gap-2">
              <Trophy className="w-5 h-5 text-amber-500"/> Trophy Cabinet
            </h2>
            {trophies.length === 0 ? (
              <div className="py-8 text-center bg-[#070B14] rounded-2xl border border-white/5">
                <p className="text-sm font-bold text-gray-500">No trophies earned yet.</p>
              </div>
            ) : (
              <div className="flex gap-4 overflow-x-auto pb-2 custom-scrollbar">
                {trophies.map(t => (
                  <div key={t.id} className="min-w-[140px] bg-[#070B14] border border-[#1E293B] p-4 rounded-2xl flex flex-col items-center justify-center shrink-0 shadow-lg">
                    <Trophy className={`w-10 h-10 mb-3 ${t.position === 1 ? 'text-amber-400 drop-shadow-[0_0_10px_rgba(251,191,36,0.4)]' : 'text-gray-400'}`} />
                    <span className="text-xs font-black text-white text-center line-clamp-1">{t.leagueName}</span>
                    <span className="text-[10px] font-bold text-gray-500 mt-1">{t.position === 1 ? 'Champion' : `Rank #${t.position}`}</span>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-4 flex items-center gap-2">
              <ShieldCheck className="w-5 h-5 text-[#BEF264]"/> Recent Matches
            </h2>
            {recentMatches.length === 0 ? (
              <div className="py-8 text-center bg-[#070B14] rounded-2xl border border-white/5">
                <p className="text-sm font-bold text-gray-500">No recent match data available.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {recentMatches.map(m => (
                  <div key={m.id} className="bg-[#070B14] border border-[#1E293B] p-4 rounded-2xl flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      <div className={`w-10 h-10 rounded-full flex items-center justify-center font-black text-white text-sm ${m.result === 'W' ? 'bg-green-500/20 text-green-500 border border-green-500/30' : m.result === 'L' ? 'bg-red-500/20 text-red-500 border border-red-500/30' : 'bg-amber-500/20 text-amber-500 border border-amber-500/30'}`}>
                        {m.result}
                      </div>
                      <div>
                        <p className="text-sm font-bold text-white">vs {m.opponentName}</p>
                        <p className="text-xs text-gray-500 font-medium">{m.leagueName}</p>
                      </div>
                    </div>
                    <div className="text-lg font-black text-white tracking-widest tabular-nums">
                      {m.goalsFor} - {m.goalsAgainst}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {isOwner && usernameEditOpen && (
        <UsernameEditModal authUid={authUser.uid} current={usernameLower} onClose={() => setUsernameEditOpen(false)} onSaved={(next) => { setUsernameLower(next); setUsernameEditOpen(false); }} />
      )}
    </div>
  );
}

function StatCard({ label, value, highlight = false }: any) {
  return (
    <div className={`p-5 rounded-3xl border flex flex-col justify-center items-center shadow-lg transition-all ${highlight ? 'bg-[#BEF264]/10 border-[#BEF264]/30 text-[#BEF264]' : 'bg-[#0B1221] border-[#1E293B] text-white'}`}>
      <span className="text-2xl font-black tabular-nums">{value}</span>
      <span className={`text-xs font-bold uppercase tracking-widest mt-1 ${highlight ? 'text-[#BEF264]/80' : 'text-gray-500'}`}>{label}</span>
    </div>
  );
}
