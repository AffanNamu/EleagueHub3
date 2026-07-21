'use client';

import { useParams, useRouter } from 'next/navigation';
import { useRef } from 'react';
import { useOrganizerProfileEditor } from '@/hooks/useOrganizerProfileEditor';
import { cloudinaryOptimizedUrl } from '@/lib/cloudinary/cloudinaryUpload';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Camera, Network, Save } from 'lucide-react';

export default function OrganizerProfileEditorScreen() {
  const params = useParams();
  const router = useRouter();
  const masterLeagueId = params.id as string;

  const {
    workspace,
    workspaceLoading,
    isOwner,
    bannerUrl,
    logoUrl,
    bio,
    badge,
    socials,
    setBio,
    setBadge,
    setSocials,
    uploadingBanner,
    uploadingLogo,
    pickAndUpload,
    saving,
    error,
    savedMessage,
    save,
  } = useOrganizerProfileEditor(masterLeagueId);

  const bannerInputRef = useRef<HTMLInputElement>(null);
  const logoInputRef = useRef<HTMLInputElement>(null);

  if (workspaceLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>;
  }

  if (!workspace) {
    return <div className="text-brand-red p-4">Workspace not found.</div>;
  }

  if (!isOwner) {
    return <div className="text-brand-red p-4">Only the Master League owner can edit the organizer profile.</div>;
  }

  const handleFileChange = (kind: 'banner' | 'logo') => (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) pickAndUpload(kind, file);
    e.target.value = '';
  };

  return (
    <div className="space-y-6 max-w-3xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <Network className="w-6 h-6 text-[#38BDF8]" /> Organizer Profile
          </h1>
          <p className="text-gray-400 mt-1">Branding, bio, and public identity for {workspace.name}.</p>
        </div>
      </div>

      {error && (
        <div className="bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl text-sm">{error}</div>
      )}
      {savedMessage && (
        <div className="bg-brand-lime/10 border border-brand-lime text-brand-lime p-4 rounded-xl text-sm">{savedMessage}</div>
      )}

      {/* Banner */}
      <Glass className="p-0 overflow-hidden">
        <div className="relative h-48 bg-brand-surfaceDark group">
          {bannerUrl ? (
            <img
              src={cloudinaryOptimizedUrl(bannerUrl, { width: 1200, height: 500, crop: 'fill' })}
              alt="Banner"
              className="w-full h-full object-cover"
            />
          ) : (
            <div className="w-full h-full bg-gradient-to-r from-brand-navy to-[#0F172A]" />
          )}
          {uploadingBanner && (
            <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
              <Loader2 className="w-8 h-8 text-white animate-spin" />
            </div>
          )}
          <button
            onClick={() => bannerInputRef.current?.click()}
            disabled={uploadingBanner}
            className="absolute bottom-3 right-3 flex items-center gap-2 px-3 py-2 bg-black/60 hover:bg-black/80 text-white text-xs font-bold rounded-lg backdrop-blur-md transition-colors"
          >
            <Camera className="w-4 h-4" /> Change Banner
          </button>
          <input ref={bannerInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange('banner')} />
        </div>

        <div className="p-6 pt-0 relative">
          <div className="w-24 h-24 rounded-full border-4 border-brand-surface bg-brand-surfaceDark overflow-hidden -mt-12 relative group">
            {logoUrl ? (
              <img src={cloudinaryOptimizedUrl(logoUrl, { width: 300, height: 300, crop: 'fill' })} className="w-full h-full object-cover" alt="Logo" />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <Network className="w-8 h-8 text-gray-500" />
              </div>
            )}
            {uploadingLogo && (
              <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                <Loader2 className="w-5 h-5 text-white animate-spin" />
              </div>
            )}
            <button
              onClick={() => logoInputRef.current?.click()}
              disabled={uploadingLogo}
              className="absolute inset-0 bg-black/0 hover:bg-black/40 flex items-center justify-center opacity-0 hover:opacity-100 transition-opacity"
            >
              <Camera className="w-5 h-5 text-white" />
            </button>
            <input ref={logoInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange('logo')} />
          </div>
        </div>
      </Glass>

      {/* About */}
      <Glass className="p-6 space-y-4">
        <h2 className="font-bold text-white">About Organizer</h2>
        <div>
          <label className="block text-sm font-bold text-gray-300 mb-1">Bio</label>
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            rows={5}
            maxLength={2000}
            placeholder="Tell people about your organization..."
            className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:border-[#38BDF8] resize-none"
          />
        </div>
        <div>
          <label className="block text-sm font-bold text-gray-300 mb-1">Badge Label (optional)</label>
          <input
            type="text"
            value={badge}
            onChange={(e) => setBadge(e.target.value)}
            maxLength={80}
            placeholder="e.g. Official FIFA Partner"
            className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-[#38BDF8]"
          />
        </div>
      </Glass>

      {/* Social links */}
      <Glass className="p-6 space-y-4">
        <h2 className="font-bold text-white">Official Links</h2>
        {(['facebook', 'instagram', 'x', 'youtube', 'tiktok'] as const).map((key) => (
          <div key={key}>
            <label className="block text-sm font-bold text-gray-300 mb-1 capitalize">
              {key === 'x' ? 'X / Twitter' : key} link (optional)
            </label>
            <input
              type="text"
              value={socials[key]}
              onChange={(e) => setSocials({ ...socials, [key]: e.target.value })}
              maxLength={2000}
              placeholder="https://..."
              className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-[#38BDF8]"
            />
          </div>
        ))}
      </Glass>

      <div className="flex gap-4 pb-6">
        <button
          onClick={save}
          disabled={saving}
          className="flex-1 py-4 bg-[#38BDF8] text-brand-navy font-black rounded-xl hover:bg-[#38BDF8]/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
          {saving ? 'Saving...' : 'Save Profile'}
        </button>
        <button
          onClick={() => router.push(`/master-leagues/${masterLeagueId}`)}
          className="px-6 py-4 bg-white/5 border border-white/10 text-white font-bold rounded-xl hover:bg-white/10 transition-colors"
        >
          Back to Workspace
        </button>
      </div>
    </div>
  );
}
