'use client';

import { useEffect, useState, useRef, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { onAuthStateChanged, updateProfile, User as FirebaseUser } from 'firebase/auth';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { ensureUsernameIfMissing } from '@/lib/services/userProfileRepository';
import { updateTeamBannerWeb, updateTeamBioWeb } from '@/lib/profile/teamProfileRepository';
import { useTeamProfile } from '@/hooks/useTeamProfile';
import { toDisplayUsername } from '@/lib/username';
import { useLeagues } from '@/hooks/useLeagues';

import { UsernameEditModal } from '@/components/profile/UsernameEditModal';
import { SquadPitchView } from '@/components/profile/SquadPitchView';
import { 
  Loader2, User, Trophy, ShieldCheck, Mail, Edit2, 
  Camera, AtSign, Settings, LogOut, Image as ImageIcon, Users 
} from 'lucide-react';
import Link from 'next/link';

export default function ProfileScreen() {
  const router = useRouter();
  
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [authLoading, setAuthLoading] = useState(true);

  const { leagues } = useLeagues();
  const { profile: teamProfile, stats, trophies, recentMatches, loading: profileLoading } = useTeamProfile(user?.uid || null);

  const [localDisplayName, setLocalDisplayName] = useState('');
  const [localPhotoUrl, setLocalPhotoUrl] = useState('');
  const [badges, setBadges] = useState({ staff: false, organizer: false, green: false });
  const [shareId, setShareId] = useState('');
  
  const [usernameLower, setUsernameLower] = useState('');
  const [usernameEditOpen, setUsernameEditOpen] = useState(false);
  const usernameEnsureTriggeredRef = useRef(false);

  // Upload Refs
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const bannerInputRef = useRef<HTMLInputElement>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [uploadingBanner, setUploadingBanner] = useState(false);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (currentUser) => {
      setUser(currentUser);
      if (currentUser) {
        setLocalDisplayName(currentUser.displayName || '');
        setLocalPhotoUrl(currentUser.photoURL || '');
      }
      setAuthLoading(false);
    });
    return () => unsubscribe();
  }, []);

  useEffect(() => {
    const fetchUserData = async () => {
      if (!user?.uid) return;
      try {
        const userDoc = await getDoc(doc(db, 'users', user.uid));
        if (userDoc.exists()) {
          const data = userDoc.data();
          const v = data.verification || {};
          setBadges({
            staff: v.staffVerified === true,
            organizer: v.organizerVerified === true || data.isVerifiedOrganizer === true,
            green: v.greenVerified === true || data.verifiedBadge === true,
          });
          setShareId(data.shareId || `eS${user.uid.substring(0, 8)}`);

          const lower = typeof data.usernameLower === 'string' ? data.usernameLower.trim() : '';
          setUsernameLower(lower);

          if (!lower && !usernameEnsureTriggeredRef.current) {
            usernameEnsureTriggeredRef.current = true;
            ensureUsernameIfMissing(user.uid, data.teamName?.trim() || user.displayName?.trim() || 'user', lower).catch(console.error);
          }
        }
      } catch (err) {
        console.error("Error fetching user data", err);
      }
    };
    if (user && !authLoading) fetchUserData();
  }, [user, authLoading]);

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;
    setUploadingAvatar(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/users' });
      await updateDoc(doc(db, 'users', user.uid), {
        photoUrl: secureUrl, profileImageUrl: secureUrl, teamImageUrl: secureUrl, updatedAt: Date.now()
      });
      await updateProfile(user, { photoURL: secureUrl });
      setLocalPhotoUrl(secureUrl);
    } catch (error: any) {
      alert(error.message);
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleBannerUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;
    setUploadingBanner(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/banners' });
      await updateTeamBannerWeb(user.uid, secureUrl);
    } catch (error: any) {
      alert(error.message);
    } finally {
      setUploadingBanner(false);
    }
  };

  const handleEditName = async () => {
    const newName = window.prompt("Enter your new profile/team name:", localDisplayName);
    if (!newName || newName.trim() === '' || newName === localDisplayName || !user) return;
    try {
      await updateDoc(doc(db, 'users', user.uid), { teamName: newName.trim(), displayName: newName.trim(), updatedAt: Date.now() });
      await updateProfile(user, { displayName: newName.trim() });
      setLocalDisplayName(newName.trim());
    } catch (error) {
      alert("Failed to update name.");
    }
  };

  const handleEditBio = async () => {
    const newBio = window.prompt("Enter your bio:", teamProfile?.bio || '');
    if (newBio !== null && user) {
      await updateTeamBioWeb(user.uid, newBio);
    }
  };

  if (authLoading || profileLoading) {
    return <div className="flex justify-center items-center h-[50vh]"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center h-[50vh] text-gray-400">
        <User className="w-12 h-12 mb-4 opacity-50"/>
        <p>Please log in to view your profile.</p>
        <button onClick={() => router.push('/login')} className="mt-4 px-6 py-2 bg-[#BEF264] text-[#0F172A] font-bold rounded-lg">Go to Login</button>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto pb-20 animate-in fade-in duration-300">
      
      {/* ── COVER & HEADER ── */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl shadow-2xl overflow-hidden mb-6">
        <div className="relative h-48 md:h-64 bg-slate-900 group">
          {teamProfile?.bannerImageUrl ? (
            <img src={teamProfile.bannerImageUrl} className="w-full h-full object-cover opacity-80" alt="Cover" />
          ) : (
            <div className="absolute inset-0 bg-gradient-to-br from-[#BEF264]/20 to-[#070B14]" />
          )}
          
          <button onClick={() => bannerInputRef.current?.click()} className="absolute top-4 right-4 p-3 bg-black/50 hover:bg-black/80 rounded-xl backdrop-blur text-white transition-colors border border-white/10 shadow-lg z-10 flex items-center gap-2">
            {uploadingBanner ? <Loader2 className="w-4 h-4 animate-spin"/> : <ImageIcon className="w-4 h-4"/>}
            <span className="text-xs font-bold hidden sm:inline">Edit Cover</span>
          </button>
          <input type="file" ref={bannerInputRef} onChange={handleBannerUpload} accept="image/*" className="hidden" />

          {/* Avatar overlaps the bottom edge */}
          <div className="absolute -bottom-12 left-6 md:left-10 flex items-end">
            <div onClick={() => !uploadingAvatar && avatarInputRef.current?.click()} className="relative w-28 h-28 md:w-32 md:h-32 rounded-full border-4 border-[#0B1221] bg-[#1E293B] shadow-2xl overflow-hidden cursor-pointer group/avatar">
              {localPhotoUrl ? (
                <img src={localPhotoUrl} className="w-full h-full object-cover group-hover/avatar:opacity-50 transition-opacity" alt="Avatar" />
              ) : (
                <User className="w-12 h-12 m-auto text-gray-500 mt-8 group-hover/avatar:opacity-50"/>
              )}
              <div className="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 group-hover/avatar:opacity-100 transition-opacity">
                {uploadingAvatar ? <Loader2 className="w-6 h-6 text-white animate-spin"/> : <Camera className="w-6 h-6 text-white"/>}
              </div>
              <input type="file" ref={avatarInputRef} onChange={handleAvatarUpload} accept="image/*" className="hidden" />
            </div>
          </div>
        </div>

        <div className="pt-16 pb-8 px-6 md:px-10">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <div>
              <h1 className="text-2xl md:text-3xl font-black text-white flex items-center gap-2">
                {localDisplayName || 'eSports Player'}
                <button onClick={handleEditName} className="p-1 text-gray-500 hover:text-[#BEF264] transition-colors"><Edit2 className="w-4 h-4"/></button>
                {badges.green && <ShieldCheck className="w-5 h-5 text-[#22C55E]"/>}
                {badges.organizer && <ShieldCheck className="w-5 h-5 text-amber-500"/>}
              </h1>
              
              <div className="flex items-center gap-4 mt-2">
                <div className="flex items-center gap-1.5 text-[#BEF264] font-bold text-sm bg-[#BEF264]/10 px-3 py-1 rounded-lg">
                  <AtSign className="w-3.5 h-3.5"/>
                  {usernameLower ? toDisplayUsername(usernameLower) : 'Setup username'}
                  <button onClick={() => setUsernameEditOpen(true)} className="ml-1 text-[#BEF264]/60 hover:text-[#BEF264]"><Edit2 className="w-3 h-3"/></button>
                </div>
                <div className="text-gray-500 text-sm font-mono flex items-center gap-2">
                  #{shareId}
                </div>
              </div>
            </div>

            <div className="flex gap-2">
              <button onClick={() => router.push('/settings')} className="p-3 bg-[#1E293B] hover:bg-[#2A3A52] text-white rounded-xl transition-colors shadow-md border border-white/5">
                <Settings className="w-5 h-5"/>
              </button>
              <button onClick={() => auth.signOut().then(()=>router.push('/login'))} className="p-3 bg-red-500/10 hover:bg-red-500/20 text-red-500 rounded-xl transition-colors shadow-md border border-red-500/20">
                <LogOut className="w-5 h-5"/>
              </button>
            </div>
          </div>

          <div className="mt-6">
            <p className="text-sm text-gray-400 font-medium leading-relaxed max-w-2xl">
              {teamProfile?.bio || "No bio added yet. Tell the community about your playstyle or achievements."}
            </p>
            <button onClick={handleEditBio} className="text-xs font-bold text-[#BEF264] hover:underline mt-2">Edit Bio</button>
          </div>
        </div>
      </div>

      {/* ── STATS ROW ── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <StatCard label="Followers" value={stats?.followersCount || 0}/>
        <StatCard label="Matches" value={stats?.matchesPlayed || 0}/>
        <StatCard highlight label="Win Rate" value={`${(stats?.winPercentage || 0).toFixed(0)}%`} />
        <StatCard label="Trophies" value={stats?.trophies || 0}/>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* ── SQUAD PREVIEW ── */}
        <div className="lg:col-span-1 space-y-6">
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-black text-white flex items-center gap-2">
                <Users className="w-5 h-5 text-[#38BDF8]"/> My Squad
              </h2>
              <button onClick={() => router.push(`/profile/squad`)} className="text-xs font-bold text-[#38BDF8] hover:underline">Edit</button>
            </div>
            
            {/* Embedded Pitch Preview.
                NOTE: gameId must be "local_football" (with underscore) —
                this is GameId.localFootball's Firestore doc id on
                mobile. Previously this was "localFootball", which read
                the squad from an entirely different document than the
                mobile app writes to. */}
            <div className="relative w-full aspect-[2/3] bg-[#070B14] rounded-2xl border border-white/10 overflow-hidden cursor-pointer group" onClick={() => router.push(`/profile/squad`)}>
               <SquadPitchView gameId="local_football" isPreview userId={user.uid}/>
               <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity backdrop-blur-[2px]">
                 <span className="text-white font-black bg-[#38BDF8] px-4 py-2 rounded-xl shadow-lg shadow-[#38BDF8]/20">Manage Squad</span>
               </div>
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
                <p className="text-sm font-bold text-gray-500">No trophies earned yet. Compete to fill your cabinet!</p>
              </div>
            ) : (
              <div className="flex gap-4 overflow-x-auto pb-2 custom-scrollbar">
                {trophies.map(t => (
                  <div key={t.id} className="min-w-[140px] bg-[#070B14] border border-[#1E293B] p-4 rounded-2xl flex flex-col items-center justify-center shrink-0 shadow-lg">
                    <Trophy className={`w-10 h-10 mb-3 ${t.position === 1 ? 'text-amber-400 drop-shadow-[0_0_10px_rgba(251,191,36,0.4)]' : 'text-gray-400'}`}/>
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

      {usernameEditOpen && (
        <UsernameEditModal authUid={user.uid} current={usernameLower} onClose={() => setUsernameEditOpen(false)}
          onSaved={(next) => { setUsernameLower(next); setUsernameEditOpen(false); }}
        />
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
