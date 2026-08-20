/*app/(dashbord)/profile/page.tsx*/
'use client';

import { useMemo, useEffect, useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { onAuthStateChanged, updateProfile, User as FirebaseUser } from 'firebase/auth';
import { useLeagues } from '@/hooks/useLeagues';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { ensureUsernameIfMissing } from '@/lib/services/userProfileRepository';
import { toDisplayUsername } from '@/lib/username';
import { UsernameEditModal } from '@/components/profile/UsernameEditModal';
import { Loader2, User, Trophy, ShieldCheck, Mail, ShieldAlert, ArrowRight, Settings, LogOut, Copy, BadgeCheck, Edit2, Camera, AtSign } from 'lucide-react';
import Link from 'next/link';

export default function ProfileScreen() {
  const router = useRouter();
  const { leagues, loading: leaguesLoading } = useLeagues();
  
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [authLoading, setAuthLoading] = useState(true);

  // Local state for immediate UI updates without refreshing
  const [localDisplayName, setLocalDisplayName] = useState('');
  const [localPhotoUrl, setLocalPhotoUrl] = useState('');

  const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  const isSuperAdmin = user?.uid === SUPER_ADMIN_UID;

  const [badges, setBadges] = useState({ staff: false, organizer: false, green: false });
  const [shareId, setShareId] = useState('');

  // NEW: username state + edit modal. usernameLower mirrors the Flutter
  // app's UserProfile.usernameLower — canonical, lowercase, unique.
  const [usernameLower, setUsernameLower] = useState('');
  const [usernameEditOpen, setUsernameEditOpen] = useState(false);
  // Guards ensureUsernameIfMissing() so it only fires once per mount,
  // same purpose as _usernameEnsureTriggered in profile_screen.dart.
  const usernameEnsureTriggeredRef = useRef(false);

  // Image Upload State
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

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

          if (data.shareId) {
            setShareId(data.shareId);
          } else {
            setShareId(`eS${user.uid.substring(0, 8)}`);
          }

          // NEW: username — read, and lazily assign one if missing.
          const lower = typeof data.usernameLower === 'string' ? data.usernameLower.trim() : '';
          setUsernameLower(lower);

          if (!lower && !usernameEnsureTriggeredRef.current) {
            usernameEnsureTriggeredRef.current = true;
            const teamNameForBase =
              (typeof data.teamName === 'string' && data.teamName.trim()) ||
              (user.displayName?.trim() || '') ||
              'user';
            ensureUsernameIfMissing(user.uid, teamNameForBase, lower).catch((err) => {
              console.error('[ProfileScreen] ensureUsernameIfMissing failed:', err);
            });
          }
        }
      } catch (err) {
        console.error("Error fetching user data", err);
      }
    };
    
    if (user && !authLoading) {
      fetchUserData();
    }
  }, [user, authLoading]);

  const { myTournaments, myMemberships } = useMemo(() => {
    const uid = user?.uid;
    if (!uid) return { myTournaments: [], myMemberships: [] };

    return {
      myTournaments: leagues.filter(l => l.organizerId === uid),
      myMemberships: leagues.filter(l => l.memberIds?.includes(uid) && l.organizerId !== uid)
    };
  }, [leagues, user]);

  if (authLoading) {
    return <div className="flex justify-center items-center h-[50vh]"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>;
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center h-[50vh] text-gray-400">
        <User className="w-12 h-12 mb-4 opacity-50" />
        <p>Please log in to view your profile.</p>
        <button onClick={() => router.push('/login')} className="mt-4 px-6 py-2 bg-brand-lime text-brand-navy font-bold rounded-lg">Go to Login</button>
      </div>
    );
  }

  const handleLogout = async () => {
    await auth.signOut();
    router.push('/login');
  };

  const handleCopyShareId = () => {
    if (!shareId) return;
    navigator.clipboard.writeText(shareId);
    alert(`Copied: ${shareId}`);
  };

  // RESTORED: Image Upload Logic
  const handleAvatarClick = () => {
    if (!uploadingAvatar) fileInputRef.current?.click();
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    
    // Check file size (5MB max)
    if (file.size > 5 * 1024 * 1024) {
      alert("Image is too large. Please select an image under 5MB.");
      return;
    }

    setUploadingAvatar(true);
    try {
      const { secureUrl } = await uploadImageFile({ 
        file, 
        folder: 'eleaguehub/users' 
      });

      // Update Firestore
      await updateDoc(doc(db, 'users', user.uid), {
        photoUrl: secureUrl,
        profileImageUrl: secureUrl,
        teamImageUrl: secureUrl,
        updatedAt: Date.now()
      });

      // Update Firebase Auth Profile
      await updateProfile(user, { photoURL: secureUrl });
      
      // Update local state instantly
      setLocalPhotoUrl(secureUrl);
    } catch (error: any) {
      console.error("Upload failed", error);
      alert(error.message || "Failed to upload image.");
    } finally {
      setUploadingAvatar(false);
      // Reset input so they can select the same file again if needed
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  // RESTORED: Edit Name Logic
  const handleEditName = async () => {
    const newName = window.prompt("Enter your new profile/team name:", localDisplayName);
    if (!newName || newName.trim() === '' || newName === localDisplayName) return;

    const cleanName = newName.trim();
    
    try {
      // Update Firestore
      await updateDoc(doc(db, 'users', user.uid), {
        teamName: cleanName,
        displayName: cleanName,
        updatedAt: Date.now()
      });

      // Update Firebase Auth Profile
      await updateProfile(user, { displayName: cleanName });
      
      // Update local state instantly
      setLocalDisplayName(cleanName);
    } catch (error) {
      console.error("Failed to update name", error);
      alert("Failed to update name. Please try again.");
    }
  };

  const renderBadge = () => {
    if (badges.staff) {
      return (
        <span title="Staff / Ambassador" className="flex items-center justify-center">
          <BadgeCheck className="w-6 h-6 text-[#E9D5FF] fill-[#9333EA] drop-shadow-[0_0_8px_rgba(147,51,234,0.9)]" />
        </span>
      );
    }
    if (badges.organizer) {
      return (
        <span title="Official Organizer" className="flex items-center justify-center">
          <BadgeCheck className="w-6 h-6 text-[#FEF08A] fill-[#F59E0B] drop-shadow-[0_0_8px_rgba(245,158,11,0.9)]" />
        </span>
      );
    }
    if (badges.green) {
      return (
        <span title="Verified User" className="flex items-center justify-center">
          <BadgeCheck className="w-6 h-6 text-[#BBF7D0] fill-[#22C55E] drop-shadow-[0_0_8px_rgba(34,197,94,0.9)]" />
        </span>
      );
    }
    return null;
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10 animate-in fade-in duration-300">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
          <User className="w-6 h-6 text-[#38BDF8]" /> My Profile
        </h1>
        <p className="text-gray-400 mt-1 text-sm">Manage your identity and memberships.</p>
      </div>

      {/* Identity Card */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-6 md:p-8 shadow-xl">
        <div className="flex flex-col sm:flex-row items-center sm:items-start gap-6">
          
          {/* Avatar Area with Hover Upload */}
          <div 
            onClick={handleAvatarClick}
            className="w-24 h-24 bg-[#1E293B] border-2 border-[#38BDF8] rounded-full overflow-hidden shrink-0 shadow-lg relative cursor-pointer group"
          >
            <input 
              type="file" 
              ref={fileInputRef} 
              onChange={handleFileChange} 
              accept="image/*" 
              className="hidden" 
            />
            {localPhotoUrl ? (
              <img src={localPhotoUrl} alt="Profile" className="w-full h-full object-cover group-hover:opacity-50 transition-opacity" />
            ) : (
              <User className="w-12 h-12 m-auto text-gray-500 mt-6 group-hover:opacity-50 transition-opacity" />
            )}
            
            {/* Upload Overlay */}
            <div className="absolute inset-0 flex items-center justify-center bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity">
              {uploadingAvatar ? (
                <Loader2 className="w-6 h-6 text-white animate-spin" />
              ) : (
                <Camera className="w-6 h-6 text-white" />
              )}
            </div>
          </div>
          
          <div className="flex-1 text-center sm:text-left pt-2">
            <h2 className="text-2xl font-black text-white flex items-center justify-center sm:justify-start gap-2">
              {localDisplayName || 'eSports Player'}
              <button 
                onClick={handleEditName}
                className="p-1 text-gray-500 hover:text-white transition-colors ml-1"
                title="Edit Name"
              >
                <Edit2 className="w-4 h-4" />
              </button>
              {renderBadge()}
            </h2>

            {/* NEW: Username row */}
            <div className="flex items-center justify-center sm:justify-start gap-2 mt-1.5">
              <AtSign className="w-3.5 h-3.5 text-gray-500" />
              <span className="text-brand-lime text-sm font-bold">
                {usernameLower ? toDisplayUsername(usernameLower) : 'Setting up username…'}
              </span>
              <button
                onClick={() => setUsernameEditOpen(true)}
                className="p-1.5 text-gray-500 hover:text-white bg-[#1E293B] hover:bg-[#2A3B54] rounded-md transition-colors"
                title="Edit username"
              >
                <Edit2 className="w-3.5 h-3.5" />
              </button>
            </div>
            
            {/* Share ID with Copy Button */}
            <div className="flex items-center justify-center sm:justify-start gap-3 mt-1.5">
              <span className="text-gray-500 text-sm font-mono flex items-center gap-1">
                # {shareId || '...'}
              </span>
              <button 
                onClick={handleCopyShareId}
                className="p-1.5 text-gray-500 hover:text-white bg-[#1E293B] hover:bg-[#2A3B54] rounded-md transition-colors"
                title="Copy ID"
              >
                <Copy className="w-3.5 h-3.5" />
              </button>
            </div>

            <div className="flex items-center justify-center sm:justify-start gap-2 text-gray-400 mt-2 text-sm">
              <Mail className="w-4 h-4 text-gray-500" /> {user.email}
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="grid grid-cols-2 gap-4 mt-8 pt-6 border-t border-[#1E293B]">
          <Link href="/settings" className="flex flex-col items-center justify-center gap-2 py-4 bg-[#0F172A] border border-white/5 rounded-xl hover:bg-[#1E293B] transition-colors text-brand-lime">
            <Settings className="w-5 h-5" />
            <span className="text-xs font-bold">Settings</span>
          </Link>
          <button onClick={handleLogout} className="flex flex-col items-center justify-center gap-2 py-4 bg-[#0F172A] border border-brand-red/10 rounded-xl hover:bg-brand-red/10 transition-colors text-brand-red">
            <LogOut className="w-5 h-5" />
            <span className="text-xs font-bold">Logout</span>
          </button>
        </div>
      </div>

      {/* Super Admin Quick Links */}
      {isSuperAdmin && (
        <div className="bg-[#0B1221] rounded-2xl overflow-hidden border border-brand-red/30 shadow-xl">
          <div className="bg-brand-red/10 p-4 flex items-center gap-2 border-b border-brand-red/20">
            <ShieldAlert className="w-5 h-5 text-brand-red" />
            <h3 className="font-bold text-brand-red">Super Admin Controls</h3>
          </div>
          <div className="p-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Link href="/admin/global-chat-requests" className="flex items-center justify-between p-4 bg-[#0F172A] rounded-xl hover:bg-[#1E293B] border border-white/5 transition-colors">
              <span className="font-bold text-gray-300 text-sm">Global Chat Requests</span>
              <ArrowRight className="w-4 h-4 text-gray-500" />
            </Link>
            <div className="flex items-center justify-between p-4 bg-[#0F172A] rounded-xl border border-white/5 opacity-50 cursor-not-allowed">
              <span className="font-bold text-gray-300 text-sm">App Config (Mobile Only)</span>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* My Tournaments */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-6 flex flex-col h-full min-h-[300px] shadow-xl">
          <div className="flex items-center gap-2 mb-6 border-b border-[#1E293B] pb-4">
            <ShieldCheck className="w-5 h-5 text-brand-lime" />
            <h3 className="font-bold text-white text-lg">My Tournaments</h3>
          </div>
          {leaguesLoading ? (
            <div className="flex justify-center py-6"><Loader2 className="w-6 h-6 animate-spin text-brand-lime" /></div>
          ) : myTournaments.length === 0 ? (
            <p className="text-gray-500 text-sm flex-1 text-center mt-10">You haven't organized any leagues yet.</p>
          ) : (
            <div className="space-y-3 flex-1 overflow-y-auto pr-2 custom-scrollbar">
              {myTournaments.map(l => (
                <Link key={l.id} href={`/leagues/${l.id}`} className="flex items-center justify-between p-3.5 bg-[#0F172A] rounded-xl hover:bg-[#1E293B] border border-white/5 transition-colors group">
                  <span className="font-bold text-gray-300 group-hover:text-white transition-colors line-clamp-1 text-sm">{l.name}</span>
                  <span className="text-[10px] bg-brand-lime/10 text-brand-lime px-2 py-1 rounded-md font-bold uppercase tracking-wider shrink-0">Owner</span>
                </Link>
              ))}
            </div>
          )}
        </div>

        {/* My Memberships */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-6 flex flex-col h-full min-h-[300px] shadow-xl">
          <div className="flex items-center gap-2 mb-6 border-b border-[#1E293B] pb-4">
            <Trophy className="w-5 h-5 text-[#38BDF8]" />
            <h3 className="font-bold text-white text-lg">My Memberships</h3>
          </div>
          {leaguesLoading ? (
            <div className="flex justify-center py-6"><Loader2 className="w-6 h-6 animate-spin text-[#38BDF8]" /></div>
          ) : myMemberships.length === 0 ? (
            <p className="text-gray-500 text-sm flex-1 text-center mt-10">You haven't joined any leagues yet.</p>
          ) : (
            <div className="space-y-3 flex-1 overflow-y-auto pr-2 custom-scrollbar">
              {myMemberships.map(l => (
                <Link key={l.id} href={`/leagues/${l.id}`} className="flex items-center justify-between p-3.5 bg-[#0F172A] rounded-xl hover:bg-[#1E293B] border border-white/5 transition-colors group">
                  <span className="font-bold text-gray-300 group-hover:text-white transition-colors line-clamp-1 text-sm">{l.name}</span>
                  <span className="text-[10px] bg-[#38BDF8]/10 text-[#38BDF8] px-2 py-1 rounded-md font-bold uppercase tracking-wider shrink-0">Member</span>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>

      {usernameEditOpen && (
        <UsernameEditModal
          authUid={user.uid}
          current={usernameLower}
          onClose={() => setUsernameEditOpen(false)}
          onSaved={(next) => {
            setUsernameLower(next);
            setUsernameEditOpen(false);
          }}
        />
      )}
    </div>
  );
}
