'use client';

import { useState, useRef, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { Glass } from '@/components/ui/Glass';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { Loader2, Camera, User, Trophy, Users } from 'lucide-react';

export default function OnboardingScreen() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [username, setUsername] = useState('');
  const [role, setRole] = useState<'player' | 'organizer' | 'fan'>('player');
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [error, setError] = useState('');

  // Check if user is already onboarded
  useEffect(() => {
    const checkOnboardingStatus = async () => {
      const user = auth.currentUser;
      if (!user) {
        router.push('/login');
        return;
      }
      
      try {
        const userDoc = await getDoc(doc(db, 'users', user.uid));
        if (userDoc.exists() && userDoc.data().username) {
          // User already has a profile, send them to dashboard
          router.push('/leagues');
        } else {
          setLoading(false);
        }
      } catch (err) {
        console.error("Failed to check status", err);
        setLoading(false);
      }
    };

    // Give Firebase Auth a moment to initialize if this is a fresh reload
    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (user) checkOnboardingStatus();
      else router.push('/login');
    });

    return () => unsubscribe();
  }, [router]);

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setAvatarFile(file);
      setAvatarPreview(URL.createObjectURL(file));
    }
  };

  const handleCompleteProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username.trim() || !auth.currentUser) {
      setError('Username is required.');
      return;
    }

    setSaving(true);
    setError('');

    try {
      let avatarUrl = '';
      if (avatarFile) {
        avatarUrl = await uploadImageToCloudinary(avatarFile);
      } else {
        avatarUrl = auth.currentUser.photoURL || '';
      }

      // Create the core user document mapping to your Flutter models
      const userRef = doc(db, 'users', auth.currentUser.uid);
      await setDoc(userRef, {
        uid: auth.currentUser.uid,
        email: auth.currentUser.email,
        username: username.trim(),
        role: role,
        avatarUrl: avatarUrl,
        isPremium: false,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }, { merge: true }); // Merge in case auth triggers created a stub document earlier

      router.push('/leagues');
    } catch (err: any) {
      console.error(err);
      setError('Failed to save profile: ' + err.message);
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <GlassScaffold>
        <div className="flex items-center justify-center min-h-[80vh]">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      </GlassScaffold>
    );
  }

  return (
    <GlassScaffold>
      <div className="flex items-center justify-center min-h-[85vh] py-10">
        <Glass className="w-full max-w-lg p-8">
          <div className="text-center mb-8">
            <h1 className="text-3xl font-black text-white tracking-tight">Complete Your Profile</h1>
            <p className="text-gray-400 mt-2">Welcome to eSportlyic. Tell us a bit about yourself.</p>
          </div>

          {error && (
            <div className="bg-brand-red/20 border border-brand-red text-brand-red p-3 rounded-lg mb-6 text-sm text-center">
              {error}
            </div>
          )}

          <form onSubmit={handleCompleteProfile} className="space-y-8">
            {/* Avatar Upload */}
            <div className="flex flex-col items-center">
              <div className="relative group cursor-pointer" onClick={() => fileInputRef.current?.click()}>
                <div className="w-24 h-24 rounded-full overflow-hidden bg-brand-surfaceDark border-2 border-dashed border-white/20 group-hover:border-brand-lime transition-colors flex items-center justify-center">
                  {avatarPreview ? (
                    <img src={avatarPreview} alt="Avatar Preview" className="w-full h-full object-cover" />
                  ) : (
                    <Camera className="w-8 h-8 text-gray-500 group-hover:text-brand-lime transition-colors" />
                  )}
                </div>
                <div className="absolute bottom-0 right-0 bg-brand-lime p-1.5 rounded-full text-brand-navy shadow-lg">
                  <Camera className="w-4 h-4" />
                </div>
              </div>
              <input type="file" ref={fileInputRef} onChange={handleImageChange} accept="image/*" className="hidden" />
              <p className="text-xs text-gray-400 mt-3">Upload Profile Picture (Optional)</p>
            </div>

            {/* Username */}
            <div>
              <label className="block text-sm font-bold text-gray-300 mb-2">Username</label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="e.g. ProGamer99"
                className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:outline-none focus:border-brand-lime transition-colors font-medium"
                required
                maxLength={20}
              />
            </div>

            {/* Role Selection */}
            <div>
              <label className="block text-sm font-bold text-gray-300 mb-3">Primary Role</label>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <button
                  type="button"
                  onClick={() => setRole('player')}
                  className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all ${role === 'player' ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400 hover:bg-white/5'}`}
                >
                  <User className="w-6 h-6 mb-2" />
                  <span className="text-sm font-bold">Player</span>
                </button>
                <button
                  type="button"
                  onClick={() => setRole('organizer')}
                  className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all ${role === 'organizer' ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400 hover:bg-white/5'}`}
                >
                  <Trophy className="w-6 h-6 mb-2" />
                  <span className="text-sm font-bold">Organizer</span>
                </button>
                <button
                  type="button"
                  onClick={() => setRole('fan')}
                  className={`flex flex-col items-center justify-center p-4 rounded-xl border transition-all ${role === 'fan' ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/5 text-gray-400 hover:bg-white/5'}`}
                >
                  <Users className="w-6 h-6 mb-2" />
                  <span className="text-sm font-bold">Fan / Viewer</span>
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={saving || !username.trim()}
              className="w-full bg-brand-lime text-brand-navy font-black py-4 rounded-xl hover:bg-brand-lime/90 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 mt-4 shadow-lg shadow-brand-lime/20"
            >
              {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Enter Platform'}
            </button>
          </form>
        </Glass>
      </div>
    </GlassScaffold>
  );
}
