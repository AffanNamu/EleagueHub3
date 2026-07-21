/*dashboard/leagues/create*/

'use client';

import { useState, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { collection, doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Image as ImageIcon, Trophy, ShieldAlert, Globe, LayoutGrid, ListOrdered } from 'lucide-react';
import { LeagueFormat, FootballCategory, LeaguePrivacy, WorldCupFormat } from '@/types/league';

export default function CreateLeagueScreen() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  // Basic Details
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  
  // Advanced Settings mapped to Flutter
  const [format, setFormat] = useState<LeagueFormat>('classic');
  const [category, setCategory] = useState<FootballCategory>('localFootball');
  const [privacy, setPrivacy] = useState<LeaguePrivacy>('public');
  const [maxTeams, setMaxTeams] = useState<number>(20);
  const [homeAwayEnabled, setHomeAwayEnabled] = useState(true);
  
  // World Cup Specific Settings
  const [worldCupFormat, setWorldCupFormat] = useState<WorldCupFormat>('fifa2022');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setCoverFile(file);
      setCoverPreview(URL.createObjectURL(file));
    }
  };

  const handleFormatChange = (newFormat: LeagueFormat) => {
    setFormat(newFormat);
    if (newFormat === 'worldCup') {
      setMaxTeams(worldCupFormat === 'fifa2022' ? 32 : 48);
      setHomeAwayEnabled(false); // World Cup has no home/away leagues usually
    }
  };

  const handleCreateLeague = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setError('League name is required.');
      return;
    }
    if (!auth.currentUser) return;

    setLoading(true);
    setError('');

    try {
      let coverImageUrl = '';
      if (coverFile) {
        coverImageUrl = await uploadImageToCloudinary(coverFile);
      }

      const leagueRef = doc(collection(db, 'leagues'));
      const nowMs = Date.now();
      
      const newLeague = {
        id: leagueRef.id,
        name: name.trim(),
        description: description.trim(),
        organizerId: auth.currentUser.uid,
        coverImageUrl: coverImageUrl,
        format: format,
        privacy: privacy,
        footballCategory: category,
        homeAwayEnabled: homeAwayEnabled,
        maxTeams: format === 'worldCup' ? (worldCupFormat === 'fifa2022' ? 32 : 48) : maxTeams,
        settings: {
          doubleRoundRobin: homeAwayEnabled,
          groupSize: 4,
          swissRounds: 8,
          ...(format === 'worldCup' && { worldCupFormat: worldCupFormat })
        },
        status: 'draft',
        participantsCount: 0,
        createdAt: serverTimestamp(),
        updatedAtMs: nowMs,
      };

      await setDoc(leagueRef, newLeague);

      // Make creator the owner
      const memberRef = doc(db, 'leagues', leagueRef.id, 'members', auth.currentUser.uid);
      await setDoc(memberRef, {
        role: 'owner',
        joinedAt: serverTimestamp(),
      });

      router.push(`/leagues/${leagueRef.id}`);
    } catch (err: any) {
      console.error(err);
      setError('Failed to create league: ' + err.message);
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <Trophy className="w-6 h-6 text-brand-lime" />
            Create Tournament
          </h1>
          <p className="text-gray-400 mt-1">Advanced League Creation Wizard</p>
        </div>
      </div>

      <form onSubmit={handleCreateLeague} className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left Column: Basic Details */}
        <div className="lg:col-span-2 space-y-6">
          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-4">Basic Information</h2>
            {error && (
              <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-3 rounded-xl mb-4">
                <ShieldAlert className="w-5 h-5 flex-shrink-0" />
                <span className="text-sm">{error}</span>
              </div>
            )}
            
            <div className="space-y-4">
              <div 
                onClick={() => fileInputRef.current?.click()}
                className="w-full h-48 rounded-2xl border-2 border-dashed border-white/20 hover:border-brand-lime bg-brand-surfaceDark flex flex-col items-center justify-center cursor-pointer transition-colors relative group overflow-hidden"
              >
                {coverPreview ? (
                  <img src={coverPreview} alt="Cover Preview" className="w-full h-full object-cover" />
                ) : (
                  <>
                    <ImageIcon className="w-10 h-10 text-gray-500 group-hover:text-brand-lime mb-2" />
                    <span className="text-sm text-gray-400 group-hover:text-brand-lime">Upload Banner Image</span>
                  </>
                )}
              </div>
              <input type="file" ref={fileInputRef} onChange={handleImageChange} accept="image/*" className="hidden" />

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">League Name *</label>
                <input
                  type="text" value={name} onChange={(e) => setName(e.target.value)} required
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime"
                  placeholder="e.g. Summer Championship"
                />
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Description</label>
                <textarea
                  value={description} onChange={(e) => setDescription(e.target.value)} rows={3}
                  className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-lime resize-none"
                  placeholder="Rules, schedule, info..."
                />
              </div>
            </div>
          </Glass>

          {/* Tournament Format Section */}
          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-4">Tournament Format</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
              {[
                { id: 'classic', label: 'Classic', icon: ListOrdered },
                { id: 'uclGroup', label: 'Group', icon: LayoutGrid },
                { id: 'uclSwiss', label: 'Swiss', icon: ShieldAlert },
                { id: 'worldCup', label: 'World Cup', icon: Globe }
              ].map((f) => {
                const Icon = f.icon;
                return (
                  <button
                    key={f.id} type="button"
                    onClick={() => handleFormatChange(f.id as LeagueFormat)}
                    className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-colors ${
                      format === f.id ? 'bg-brand-lime/10 border-brand-lime text-brand-lime' : 'bg-brand-surface border-white/10 text-gray-400 hover:bg-white/5'
                    }`}
                  >
                    <Icon className="w-6 h-6" />
                    <span className="text-xs font-bold">{f.label}</span>
                  </button>
                )
              })}
            </div>

            {format === 'worldCup' && (
              <div className="p-4 bg-brand-surface border border-white/5 rounded-xl">
                <label className="block text-sm font-bold text-gray-300 mb-2">World Cup Generation Engine</label>
                <select 
                  value={worldCupFormat} 
                  onChange={(e) => {
                    setWorldCupFormat(e.target.value as WorldCupFormat);
                    setMaxTeams(e.target.value === 'fifa2022' ? 32 : 48);
                  }}
                  className="w-full bg-brand-surfaceDark border border-white/10 rounded-lg p-2 text-white"
                >
                  <option value="fifa2022">FIFA 2022 Format (32 Teams, 8 Groups)</option>
                  <option value="fifa2026">FIFA 2026 Format (48 Teams, 12 Groups)</option>
                </select>
              </div>
            )}
          </Glass>
        </div>

        {/* Right Column: Settings & Configuration */}
        <div className="space-y-6">
          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-4">Configuration</h2>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Category</label>
                <select value={category} onChange={(e) => setCategory(e.target.value as FootballCategory)} className="w-full bg-brand-surface border border-white/10 rounded-lg p-2 text-white">
                  <option value="localFootball">Local Football</option>
                  <option value="proFootball">Pro Football</option>
                  <option value="esports">eSports</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Privacy</label>
                <select value={privacy} onChange={(e) => setPrivacy(e.target.value as LeaguePrivacy)} className="w-full bg-brand-surface border border-white/10 rounded-lg p-2 text-white">
                  <option value="public">Public (Searchable)</option>
                  <option value="private">Private (Invite Only)</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-300 mb-1">Max Teams</label>
                <input 
                  type="number" value={maxTeams} onChange={(e) => setMaxTeams(parseInt(e.target.value) || 20)}
                  disabled={format === 'worldCup'}
                  className="w-full bg-brand-surface border border-white/10 rounded-lg p-2 text-white disabled:opacity-50"
                />
              </div>

              <div className="flex items-center justify-between pt-2">
                <label className="text-sm font-bold text-gray-300">Home & Away Legs</label>
                <input 
                  type="checkbox" 
                  checked={homeAwayEnabled} 
                  onChange={(e) => setHomeAwayEnabled(e.target.checked)}
                  disabled={format === 'worldCup'}
                  className="w-5 h-5 accent-brand-lime"
                />
              </div>
            </div>
          </Glass>

          <button
            type="submit"
            disabled={loading || !name.trim()}
            className="w-full py-4 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-brand-lime/20"
          >
            {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Trophy className="w-5 h-5" />}
            Create Tournament
          </button>
        </div>
      </form>
    </div>
  );
}
