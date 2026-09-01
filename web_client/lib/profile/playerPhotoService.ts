export interface PlayerSearchCandidate {
  id: string;
  name: string;
  team: string;
  nationality: string;
  position: string;
  previewPhotoUrl: string;
  bestPhotoUrl: string;
}

const THE_SPORTS_DB_KEY = '3'; // Free tier key
const BASE_URL = `https://www.thesportsdb.com/api/v1/json/${THE_SPORTS_DB_KEY}/searchplayers.php?p=`;

export async function searchPlayersWeb(query: string): Promise<PlayerSearchCandidate[]> {
  const trimmed = query.trim();
  if (trimmed.length < 3) return [];

  try {
    const res = await fetch(`${BASE_URL}${encodeURIComponent(trimmed.replace(/ /g, '_'))}`);
    if (!res.ok) throw new Error('Player search failed');

    const data = await res.json();
    if (!data.player) return [];

    const candidates = data.player
      .filter((p: any) => (p.strSport || '').toLowerCase() === 'soccer')
      .map((p: any) => {
        const cutout = (p.strCutout || '').trim();
        const thumb = (p.strThumb || '').trim();
        return {
          id: p.idPlayer || '',
          name: p.strPlayer || '',
          team: p.strTeam || '',
          nationality: p.strNationality || '',
          position: p.strPosition || '',
          previewPhotoUrl: thumb || cutout,
          bestPhotoUrl: cutout || thumb,
        };
      })
      .filter((c: PlayerSearchCandidate) => c.name !== '');

    // Sort active players (with teams) to the top
    return candidates.sort((a: PlayerSearchCandidate, b: PlayerSearchCandidate) => {
      const aHasTeam = a.team.length > 0;
      const bHasTeam = b.team.length > 0;
      if (aHasTeam === bHasTeam) return 0;
      return aHasTeam ? -1 : 1;
    });
  } catch (err) {
    console.error('[PlayerPhotoService] search failed:', err);
    return [];
  }
}

// Cloudinary natively supports passing a remote URL to the "file" parameter
// to automatically ingest and re-host it.
export async function resolvePhotoUrlWeb(sourceUrl: string): Promise<string> {
  if (!sourceUrl.trim()) return '';

  const cloudName = process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME;
  const uploadPreset = process.env.NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET;
  if (!cloudName || !uploadPreset) throw new Error("Cloudinary not configured");

  const formData = new FormData();
  formData.append('file', sourceUrl); // Pass the remote URL directly
  formData.append('upload_preset', uploadPreset);
  formData.append('folder', 'eleaguehub/players');

  const res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error('Cloudinary ingestion failed');
  const data = await res.json();
  return data.secure_url;
}
