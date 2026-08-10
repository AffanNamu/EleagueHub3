'use client';

import { useMemo, useState } from 'react';
import { X, Download, Share2, Loader2 } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';
import {
  MATCH_POSTER_SIZES,
  MATCH_POSTER_FORMAT_LABELS,
  MatchPosterFormat,
} from '@/lib/models/matchPoster';

interface MatchPosterModalProps {
  leagueId: string;
  matchId: string;
  onClose: () => void;
}

const FORMATS: MatchPosterFormat[] = ['portrait', 'square', 'story'];

export function MatchPosterModal({ leagueId, matchId, onClose }: MatchPosterModalProps) {
  const [format, setFormat] = useState<MatchPosterFormat>('portrait');
  const [dateTime, setDateTime] = useState('');
  const [venue, setVenue] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const posterUrl = useMemo(() => {
    const params = new URLSearchParams({ format });
    if (dateTime.trim()) params.set('dateTime', dateTime.trim().slice(0, 40));
    if (venue.trim()) params.set('venue', venue.trim().slice(0, 40));
    return `/api/leagues/${leagueId}/matches/${matchId}/poster?${params.toString()}`;
  }, [leagueId, matchId, format, dateTime, venue]);

  const size = MATCH_POSTER_SIZES[format];

  async function handleShare() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(posterUrl);
      if (!res.ok) throw new Error('Could not generate the poster.');
      const blob = await res.blob();
      const file = new File([blob], 'esportlyic-match-poster.png', { type: 'image/png' });

      const nav = navigator as Navigator & {
        canShare?: (data?: ShareData) => boolean;
        share?: (data: ShareData) => Promise<void>;
      };

      if (nav.canShare && nav.canShare({ files: [file] }) && nav.share) {
        await nav.share({ files: [file], text: 'Match poster from eSportlyic' });
      } else {
        // Fallback: most desktop browsers don't yet support sharing files
        // via the Web Share API, so just trigger a download instead.
        const objectUrl = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = objectUrl;
        a.download = 'esportlyic-match-poster.png';
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(objectUrl);
      }
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') {
        // User cancelled the native share sheet — not an error.
      } else {
        console.error('[MatchPosterModal] share failed:', err);
        setError(err instanceof Error ? err.message : 'Could not share the poster.');
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <Glass className="w-full max-w-md p-5 relative max-h-[90vh] overflow-y-auto">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-lg font-black text-white mb-4">Match Poster</h3>

        <div
          className="w-full rounded-2xl overflow-hidden border border-white/10 bg-black/30 mb-4"
          style={{ aspectRatio: `${size.width} / ${size.height}` }}
        >
          {/* The API route returns the actual export bytes, so this
              preview IS the export — no separate render/export step. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            key={posterUrl}
            src={posterUrl}
            alt="Match poster preview"
            className="w-full h-full object-cover"
          />
        </div>

        <div className="mb-4">
          <div className="text-xs font-black uppercase tracking-widest text-slate-500 mb-2">
            Format
          </div>
          <div className="flex gap-2">
            {FORMATS.map((f) => (
              <button
                key={f}
                onClick={() => setFormat(f)}
                className={`px-3 py-1.5 rounded-lg text-xs font-black border transition-colors ${
                  format === f
                    ? 'bg-brand-lime/15 border-brand-lime/40 text-brand-lime'
                    : 'bg-white/[0.02] border-white/10 text-slate-400 hover:bg-white/[0.05]'
                }`}
              >
                {MATCH_POSTER_FORMAT_LABELS[f]}
              </button>
            ))}
          </div>
        </div>

        <div className="mb-4 space-y-2">
          <div className="text-xs font-black uppercase tracking-widest text-slate-500">
            Details (optional)
          </div>
          <input
            value={dateTime}
            onChange={(e) => setDateTime(e.target.value)}
            maxLength={40}
            placeholder="e.g. Saturday, 8:30 PM"
            className="w-full px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40"
          />
          <input
            value={venue}
            onChange={(e) => setVenue(e.target.value)}
            maxLength={40}
            placeholder="e.g. eSportlyic Arena"
            className="w-full px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40"
          />
        </div>

        {error && <p className="text-xs font-bold text-red-400 mb-3">{error}</p>}

        <div className="flex gap-2">
          <a
            href={posterUrl}
            download="esportlyic-match-poster.png"
            className="flex-1 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm font-black flex items-center justify-center gap-2 transition-colors"
          >
            <Download className="w-4 h-4" /> Download
          </a>
          <button
            onClick={handleShare}
            disabled={busy}
            className="flex-1 py-3 rounded-xl bg-brand-lime text-slate-900 text-sm font-black flex items-center justify-center gap-2 hover:brightness-110 transition-all disabled:opacity-60"
          >
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Share2 className="w-4 h-4" />}
            Share
          </button>
        </div>
      </Glass>
    </div>
  );
}
