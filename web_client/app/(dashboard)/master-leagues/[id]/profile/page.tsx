'use client';

import { useState, useEffect, useRef } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useMasterLeagueDetails } from '@/hooks/useMasterLeagues';
import { updateOrganizerProfileWeb } from '@/lib/masterLeagues/masterLeaguesRepository';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Save, Image as ImageIcon, Camera } from 'lucide-react';

export default function OrganizerProfileScreen() {
  const params = useParams();
  const router = useRouter();
  const mlId = params.id as string;

  const { masterLeague, loading } = useMasterLeagueDetails(mlId);
  
  const [bio, setBio] = useState('');
  const [badge, setBadge] = useState('');
  const [socials, setSocials] = useState({ facebook: '', instagram: '', x: '', youtube: '', tiktok: '' });
  const [saving, setSaving] = useState(false);

  const bannerRef = useRef<HTMLInputElement>(null);
  const logoRef = useRef<HTMLInputElement>(null);
  const [uploadingBanner, setUploadingBanner] = useState(false);
  const [uploadingLogo, setUploadingLogo] = useState(false);

  useEffect(() => {
    if (masterLeague?.organizerProfile) {
      setBio(masterLeague.organizerProfile.bio || '');
      setBadge(masterLeague.organizerProfile.badge || '');
      setSocials({
        facebook: masterLeague.organizerProfile.socialLinks?.facebook || '',
        instagram: masterLeague.organizerProfile.socialLinks?.instagram || '',
        x: masterLeague.organizerProfile.socialLinks?.x || '',
        youtube: masterLeague.organizerProfile.socialLinks?.youtube || '',
        tiktok: masterLeague.organizerProfile.socialLinks?.tiktok || ''
      });
    }
  }, [masterLeague]);

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" /></div>;
  if (!masterLeague || masterLeague.ownerId !== auth.currentUser?.uid) return <div className="text-center py-20 text-red-500 font-bold">Access Denied</div>;

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>, isBanner: boolean) => {
    const file = e.target.files?.[0];
    if (!file) return;
    
    isBanner ? setUploadingBanner(true) : setUploadingLogo(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/organizers' });
      const currentProfile = masterLeague.organizerProfile || { bannerUrl: '', logoUrl: '', bio: '', badge: '', socialLinks: {} };
      
      await updateOrganizerProfileWeb(mlId, {
        ...currentProfile,
        bannerUrl: isBanner ? secureUrl : currentProfile.bannerUrl,
        logoUrl: !isBanner ? secureUrl : currentProfile.logoUrl,
      }, auth.currentUser!.uid);
      
    } catch (err: any) {
      alert(err.message);
    } finally {
      isBanner ? setUploadingBanner(false) : setUploadingLogo(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const currentProfile = masterLeague.organizerProfile || { bannerUrl: '', logoUrl: '' };
      await updateOrganizerProfileWeb(mlId, {
        ...currentProfile, bio, badge, socialLinks: socials
      }, auth.currentUser!.uid);
      alert('Profile updated successfully!');
    } catch (err: any) {
      alert(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl md:text-2xl font-black text-white">Organizer Profile</h1>
      </div>

      <Glass className="p-6 md:p-8 bg-[#0B1221] border-[#1E293B] rounded-3xl shadow-xl">
        {/* Images */}
        <div className="relative h-48 bg-slate-900 rounded-2xl mb-12 overflow-hidden border border-[#1E293B]">
          {masterLeague.organizerProfile?.bannerUrl ? (
            <img src={masterLeague.organizerProfile.bannerUrl} className="w-full h-full object-cover opacity-70" alt="Banner" />
          ) : <div className="absolute inset-0 bg-gradient-to-br from-[#1E293B] to-[#070B14]" />}
          
          <button onClick={() => bannerRef.current?.click()} className="absolute top-4 right-4 p-2 bg-black/50 hover:bg-black/80 rounded-xl text-white backdrop-blur flex items-center gap-2">
            {uploadingBanner ? <Loader2 className="w-4 h-4 animate-spin"/> : <ImageIcon className="w-4 h-4"/>} <span className="text-xs font-bold">Banner</span>
          </button>

          <div className="absolute -bottom-8 left-6">
            <div onClick={() => logoRef.current?.click()} className="relative w-24 h-24 rounded-full border-4 border-[#0B1221] bg-[#1E293B] cursor-pointer overflow-hidden group">
              {masterLeague.organizerProfile?.logoUrl ? <img src={masterLeague.organizerProfile.logoUrl} className="w-full h-full object-cover group-hover:opacity-50" alt="Logo"/> : <Camera className="w-8 h-8 text-gray-500 m-auto mt-7 group-hover:opacity-50"/>}
              {uploadingLogo && <div className="absolute inset-0 bg-black/50 flex items-center justify-center"><Loader2 className="w-6 h-6 text-white animate-spin"/></div>}
            </div>
          </div>
          
          <input type="file" ref={bannerRef} onChange={(e) => handleImageUpload(e, true)} className="hidden" accept="image/*"/>
          <input type="file" ref={logoRef} onChange={(e) => handleImageUpload(e, false)} className="hidden" accept="image/*"/>
        </div>

        {/* Text Fields */}
        <div className="space-y-4">
          <div>
            <label className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1 block">Custom Badge (e.g. "Pro Series")</label>
            <input value={badge} onChange={e => setBadge(e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white focus:border-[#BEF264] outline-none" />
          </div>
          <div>
            <label className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1 block">Bio</label>
            <textarea value={bio} onChange={e => setBio(e.target.value)} rows={4} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white focus:border-[#BEF264] outline-none resize-none" />
          </div>

          <div className="pt-4 border-t border-[#1E293B]">
            <h3 className="text-sm font-black text-white mb-3">Social Links</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {['x', 'instagram', 'facebook', 'youtube', 'tiktok'].map(platform => (
                <div key={platform}>
                  <label className="text-[10px] font-bold text-gray-500 uppercase tracking-widest block mb-1">{platform}</label>
                  <input 
                    value={(socials as any)[platform]} 
                    onChange={e => setSocials({...socials, [platform]: e.target.value})} 
                    placeholder={`https://${platform}.com/...`}
                    className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white focus:border-[#BEF264] outline-none text-sm" 
                  />
                </div>
              ))}
            </div>
          </div>

          <button onClick={handleSave} disabled={saving} className="w-full py-4 mt-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50 flex items-center justify-center gap-2">
            {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />} Save Profile
          </button>
        </div>
      </Glass>
    </div>
  );
}
