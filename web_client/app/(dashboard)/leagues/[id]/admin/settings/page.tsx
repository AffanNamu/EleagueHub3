'use client';

import { useState, useRef, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, updateDoc, deleteDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Settings, Image as ImageIcon, Trash2, ShieldAlert, Save } from 'lucide-react';

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
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');

  // Populate form when league data loads
  useEffect(() => {
    if (league) {
      setName(league.name || '');
      setDescription(league.description || '');
      setCoverPreview(league.coverImageUrl || null);
      setPrivacy(league.privacy || 'public');
    }
  }, [league]);

  // Security check mapping to league_admin_screen.dart
  if (league && auth.currentUser?.uid !== league.organizerId) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-brand-red">
        <ShieldAlert className="w-16 h-16 mb-4" />
        <h2 className="text-xl font-bold">Access Denied</h2>
        <p>Only the league organizer can access this page.</p>
        <button onClick={() => router.back()} className="mt-4 px-4 py-2 bg-brand-surface rounded-lg text-white">Go Back</button>
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
      let updatedImageUrl = league?.coverImageUrl || '';
      if (coverFile) {
        updatedImageUrl = await uploadImageToCloudinary(coverFile);
      }

      const leagueRef = doc(db, 'leagues', leagueId);
      await updateDoc(leagueRef, {
        name: name.trim(),
        description: description.trim(),
        privacy: privacy,
        coverImageUrl: updatedImageUrl,
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

  const handleDelete = async () => {
    const confirmation = prompt(`DANGER: Type "DELETE" to permanently delete ${league?.name}. This cannot be undone.`);
    if (confirmation !== 'DELETE') return;

    setDeleting(true);
    try {
      // In a production app, you might want to call a Cloud Function to delete subcollections (matches, teams) too.
      // For now, we delete the top-level document just like the simple Dart implementation often starts with.
      await deleteDoc(doc(db, 'leagues', leagueId));
      alert("League deleted.");
      router.push('/leagues');
    } catch (err: any) {
      alert('Failed to delete league: ' + err.message);
      setDeleting(false);
    }
  };

  if (leagueLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-brand-lime" /></div>;

  return (
    <div className="space-y-6 max-w-3xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <Settings className="w-6 h-6 text-brand-lime" />
            League Settings
          </h1>
          <p className="text-gray-400 mt-1">Manage details or delete this tournament.</p>
        </div>
      </div>

      <Glass className="p-6 md:p-8">
        {error && <div className="p-3 bg-brand-red/20 text-brand-red border border-brand-red rounded-lg mb-6 text-sm">{error}</div>}

        <form onSubmit={handleUpdate} className="space-y-6">
          <div className="space-y-2">
            <label className="block text-sm font-bold text-gray-300">Update Banner</label>
            <div 
              onClick={() => fileInputRef.current?.click()}
              className="w-full h-48 rounded-2xl border-2 border-dashed border-white/20 hover:border-brand-lime bg-brand-surfaceDark flex flex-col items-center justify-center cursor-pointer overflow-hidden relative group"
            >
              {coverPreview ? (
                <>
                  <img src={coverPreview} alt="Preview" className="w-full h-full object-cover" />
                  <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity"><span className="text-white font-bold">Change Image</span></div>
                </>
              ) : (
                <ImageIcon className="w-10 h-10 text-gray-500 group-hover:text-brand-lime" />
              )}
            </div>
            <input type="file" ref={fileInputRef} onChange={handleImageChange} accept="image/*" className="hidden" />
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-300 mb-1">League Name</label>
            <input type="text" value={name} onChange={(e) => setName(e.target.value)} required className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime" />
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-300 mb-1">Description</label>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime resize-none" />
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-300 mb-1">Privacy Level</label>
            <select value={privacy} onChange={(e) => setPrivacy(e.target.value as 'public' | 'private')} className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime">
              <option value="public">Public (Searchable by anyone)</option>
              <option value="private">Private (Invite/Coupon Only)</option>
            </select>
          </div>

          <div className="pt-4 border-t border-white/5 flex flex-col sm:flex-row gap-4">
            <button type="submit" disabled={saving} className="flex-1 py-4 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2">
              {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />} Save Changes
            </button>
            
            <button type="button" onClick={handleDelete} disabled={deleting} className="px-6 py-4 bg-brand-surface border border-brand-red/30 text-brand-red font-bold rounded-xl hover:bg-brand-red/10 transition-colors flex items-center justify-center gap-2">
              {deleting ? <Loader2 className="w-5 h-5 animate-spin" /> : <Trash2 className="w-5 h-5" />} Delete League
            </button>
          </div>
        </form>
      </Glass>
    </div>
  );
}
