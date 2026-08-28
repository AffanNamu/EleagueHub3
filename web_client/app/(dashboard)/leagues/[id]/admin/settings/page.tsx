'use client';

import { useState, useRef, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, updateDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { Loader2, ArrowLeft, Settings, Image as ImageIcon, ShieldAlert, Save } from 'lucide-react';

export default function LeagueSettingsScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  const [privacy, setPrivacy] = useState<'public' | 'private'>('public');
  
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (league) {
      setName(league.name || '');
      setDescription(league.description || '');
      setCoverPreview(league.leagueImageUrl || null);
      setPrivacy(league.privacy || 'public');
    }
  }, [league]);

  if (league && auth.currentUser?.uid !== league.organizerUid && auth.currentUser?.uid !== league.ownerUid) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-red-500 bg-[#070B14] min-h-screen">
        <ShieldAlert className="w-16 h-16 mb-4" />
        <h2 className="text-xl font-black">Access Denied</h2>
        <p className="text-sm font-medium mt-2">Only the league organizer can access this page.</p>
        <button onClick={() => router.back()} className="mt-6 px-6 py-3 bg-[#1E293B] rounded-xl text-white font-bold hover:bg-[#2A3A52]">Go Back</button>
      </div>
    );
  }

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setCoverFile(file);
      setCoverPreview(URL.createObjectURL(file));
    }
  };

  const handleUpdate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return setError('Name is required.');
    
    setSaving(true);
    setError('');

    try {
      let updatedImageUrl = league?.leagueImageUrl || '';
      if (coverFile) {
        updatedImageUrl = await uploadImageToCloudinary(coverFile);
      }

      const leagueRef = doc(db, 'leagues', leagueId);
      await updateDoc(leagueRef, {
        name: name.trim(),
        description: description.trim(),
        privacy: privacy,
        leagueImageUrl: updatedImageUrl,
        updatedAtMs: Date.now(),
      });

      alert("League settings updated successfully.");
      router.push(`/leagues/${leagueId}`);
    } catch (err: any) {
      console.error(err);
      setError('Failed to update league: ' + err.message);
    } finally {
      setSaving(false);
    }
  };

  if (leagueLoading) return <div className="flex justify-center py-20 min-h-screen bg-[#070B14]"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" /></div>;

  return (
    <div className="min-h-screen bg-[#070B14] text-white font-sans pb-20">
      
      <header className="sticky top-0 z-40 bg-[#070B14]/90 backdrop-blur-md border-b border-[#1E293B] px-4 md:px-8 h-16 flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-xl font-black text-white tracking-tight flex items-center gap-2">
            <Settings className="w-5 h-5 text-[#BEF264]" /> League Settings
          </h1>
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-4 sm:px-6 mt-8">
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 md:p-8 shadow-xl">
          {error && <div className="p-4 bg-red-500/10 text-red-500 border border-red-500/20 rounded-xl mb-6 text-sm font-bold flex items-center gap-2"><ShieldAlert className="w-5 h-5" />{error}</div>}

          <form onSubmit={handleUpdate} className="space-y-6">
            <div className="space-y-3">
              <label className="block text-xs font-black uppercase tracking-widest text-gray-400">Update Banner</label>
              <div 
                onClick={() => fileInputRef.current?.click()}
                className="w-full h-48 rounded-2xl border-2 border-dashed border-[#1E293B] hover:border-[#BEF264] bg-[#070B14] flex flex-col items-center justify-center cursor-pointer overflow-hidden relative group transition-colors"
              >
                {coverPreview ? (
                  <>
                    <img src={coverPreview} alt="Preview" className="w-full h-full object-cover" />
                    <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                      <span className="text-white font-black text-sm bg-[#0B1221] px-4 py-2 rounded-xl border border-white/10">Change Image</span>
                    </div>
                  </>
                ) : (
                  <ImageIcon className="w-10 h-10 text-gray-500 group-hover:text-[#BEF264] transition-colors" />
                )}
              </div>
              <input type="file" ref={fileInputRef} onChange={handleImageChange} accept="image/*" className="hidden" />
            </div>

            <div>
              <label className="block text-xs font-black uppercase tracking-widest text-gray-400 mb-2">League Name</label>
              <input type="text" value={name} onChange={(e) => setName(e.target.value)} required className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-sm font-bold text-white focus:border-[#BEF264] outline-none transition-colors" />
            </div>

            <div>
              <label className="block text-xs font-black uppercase tracking-widest text-gray-400 mb-2">Description</label>
              <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-sm font-medium text-white focus:border-[#BEF264] outline-none transition-colors resize-none" />
            </div>

            <div>
              <label className="block text-xs font-black uppercase tracking-widest text-gray-400 mb-2">Privacy Level</label>
              <select value={privacy} onChange={(e) => setPrivacy(e.target.value as 'public' | 'private')} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-sm font-bold text-white focus:border-[#BEF264] outline-none transition-colors">
                <option value="public">Public (Searchable by anyone)</option>
                <option value="private">Private (Invite/Coupon Only)</option>
              </select>
            </div>

            <div className="pt-6 mt-6 border-t border-[#1E293B]">
              <button type="submit" disabled={saving} className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-[#BEF264]/20">
                {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />} Save Changes
              </button>
            </div>
          </form>
        </div>
      </main>
    </div>
  );
}
