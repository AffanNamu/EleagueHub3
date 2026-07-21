'use client';

import { useEffect, useState } from 'react';
import { useMasterLeagueDetail } from './useMasterLeagueDetail';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { updateOrganizerProfile } from '@/lib/masterLeagues/organizerProfileRepository';

export interface SocialLinksState {
  facebook: string;
  instagram: string;
  x: string;
  youtube: string;
  tiktok: string;
}

const EMPTY_SOCIALS: SocialLinksState = {
  facebook: '',
  instagram: '',
  x: '',
  youtube: '',
  tiktok: '',
};

export function useOrganizerProfileEditor(masterLeagueId: string) {
  const { workspace, loading: workspaceLoading, uid } = useMasterLeagueDetail(masterLeagueId);

  const [bannerUrl, setBannerUrl] = useState('');
  const [logoUrl, setLogoUrl] = useState('');
  const [bio, setBio] = useState('');
  const [badge, setBadge] = useState('');
  const [socials, setSocials] = useState<SocialLinksState>(EMPTY_SOCIALS);
  const [hydratedForId, setHydratedForId] = useState('');

  const [uploadingBanner, setUploadingBanner] = useState(false);
  const [uploadingLogo, setUploadingLogo] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [savedMessage, setSavedMessage] = useState('');

  useEffect(() => {
    if (!workspace || hydratedForId === workspace.id) return;
    const p = workspace.organizerProfile;
    setBannerUrl(p.bannerUrl);
    setLogoUrl(p.logoUrl);
    setBio(p.bio);
    setBadge(p.badge);
    setSocials({
      facebook: p.socialLinks.facebook ?? '',
      instagram: p.socialLinks.instagram ?? '',
      x: p.socialLinks.x ?? p.socialLinks.twitter ?? '',
      youtube: p.socialLinks.youtube ?? '',
      tiktok: p.socialLinks.tiktok ?? '',
    });
    setHydratedForId(workspace.id);
  }, [workspace, hydratedForId]);

  const isOwner = !!workspace && workspace.ownerId === uid;

  async function pickAndUpload(kind: 'banner' | 'logo', file: File) {
    setError('');
    const setUploading = kind === 'banner' ? setUploadingBanner : setUploadingLogo;
    setUploading(true);
    try {
      const { secureUrl } = await uploadImageFile({
        file,
        folder: 'eleaguehub/organizers',
        publicIdPrefix: kind === 'banner' ? `organizer_banner_${masterLeagueId}` : `organizer_logo_${masterLeagueId}`,
      });
      if (kind === 'banner') setBannerUrl(secureUrl);
      else setLogoUrl(secureUrl);
    } catch (e: any) {
      setError(e.message || 'Upload failed.');
    } finally {
      setUploading(false);
    }
  }

  async function save() {
    setError('');
    setSavedMessage('');
    if (!isOwner) {
      setError('Only the Master League owner can edit the organizer profile.');
      return;
    }
    setSaving(true);
    try {
      await updateOrganizerProfile(masterLeagueId, {
        bannerUrl,
        logoUrl,
        bio,
        badge,
        socialLinks: {
          facebook: socials.facebook,
          instagram: socials.instagram,
          x: socials.x,
          youtube: socials.youtube,
          tiktok: socials.tiktok,
        },
      });
      setSavedMessage('Organizer profile updated.');
    } catch (e: any) {
      setError(e.message || 'Failed to save profile.');
    } finally {
      setSaving(false);
    }
  }

  return {
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
  };
}
