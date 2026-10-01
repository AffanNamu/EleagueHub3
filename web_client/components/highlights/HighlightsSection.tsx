'use client';

// components/highlights/HighlightsSection.tsx
//
// Web port of lib/features/highlights/presentation/league_highlights_section.dart
// (+ its upload flow, normally driven by highlight_upload_controller.dart).
// Ultra-low-cost UI strategy mirrored: small list, lightweight thumbnails,
// in-app playback via a plain <video> (clips are already small, so a
// progressive <video> tag is smooth without HLS/adaptive streaming).

import { useEffect, useRef, useState } from 'react';
import { Video, UploadCloud, PlayCircle, X, Loader2, FileVideo } from 'lucide-react';
import { FixtureMatch } from '@/lib/models/leagueDetails';
import {
  MatchHighlight,
  isHighlightApproved,
  isHighlightProcessing,
  isHighlightUploading,
} from '@/lib/highlights/types';
import {
  watchHighlightsForMatch,
  getOrCreateUploadingHighlight,
  markUploadSucceeded,
  markUploadFailed,
  HighlightsUserFriendlyError,
} from '@/lib/highlights/highlightsRepository';
import { validateHighlightFile, uploadHighlightVideo, MAX_HIGHLIGHT_BYTES, MAX_HIGHLIGHT_DURATION_SECONDS } from '@/lib/highlights/highlightUpload';
import { buildLightweightThumbnailUrl } from '@/lib/highlights/types';

interface Props {
  match: FixtureMatch;
  homeTeamName: string;
  awayTeamName: string;
  isTeamMember: boolean;
  isLeagueOwner: boolean;
}

export function HighlightsSection({ match, homeTeamName, awayTeamName, isTeamMember, isLeagueOwner }: Props) {
  const [highlights, setHighlights] = useState<MatchHighlight[] | null>(null);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [playingUrl, setPlayingUrl] = useState<string | null>(null);
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const canUpload = isTeamMember || isLeagueOwner;

  useEffect(() => {
    const unsub = watchHighlightsForMatch(match.id, setHighlights);
    return () => unsub();
  }, [match.id]);

  async function doUpload(file: File, preferredTeamId?: string) {
    setError(null);
    setUploading(true);
    setProgress(0);

    let createdHighlightId: string | null = null;
    let createdMatchId: string | null = null;

    try {
      await validateHighlightFile(file);

      const { highlightId, cloudFolder } = await getOrCreateUploadingHighlight({
        match,
        isLeagueOwner,
        preferredTeamId,
      });
      createdHighlightId = highlightId;
      createdMatchId = match.id;

      const result = await uploadHighlightVideo({
        file,
        folder: cloudFolder,
        publicId: highlightId,
        onProgress: (sent, total) => setProgress(total > 0 ? sent / total : 0),
      });

      await markUploadSucceeded({
        matchId: match.id,
        highlightId,
        cloudinaryPublicId: result.publicId,
        secureUrl: result.secureUrl,
        thumbnailUrl: buildLightweightThumbnailUrl(result.secureUrl),
        duration: result.duration,
        size: result.bytes,
        format: result.format,
      });
    } catch (e: any) {
      if (createdHighlightId && createdMatchId) {
        try {
          await markUploadFailed(createdMatchId, createdHighlightId);
        } catch {
          // best-effort only
        }
      }
      setError(e instanceof HighlightsUserFriendlyError ? e.message : e?.message || 'Upload failed.');
    } finally {
      setUploading(false);
      setProgress(0);
    }
  }

  function onFilePicked(file: File) {
    if (!file) return;

    if (isTeamMember) {
      void doUpload(file);
      return;
    }

    // League-owner path with no personal team assignment: ask which team
    // this highlight belongs to before creating/uploading anything.
    setPendingFile(file);
  }

  function onInputChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) onFilePicked(file);
  }

  return (
    <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl md:col-span-2">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-base font-black text-white flex items-center gap-2">
          <Video className="w-5 h-5 text-sky-400" /> Highlights
        </h3>

        {canUpload && (
          <>
            <input ref={fileInputRef} type="file" accept="video/*" className="hidden" onChange={onInputChange} />
            <button
              onClick={() => fileInputRef.current?.click()}
              disabled={uploading}
              className="px-4 py-2 bg-sky-500/10 border border-sky-500/30 text-sky-400 text-xs font-black rounded-xl hover:bg-sky-500/20 transition-colors flex items-center gap-2 disabled:opacity-50"
            >
              {uploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <UploadCloud className="w-4 h-4" />}
              {uploading ? `Uploading ${Math.round(progress * 100)}%` : 'Upload'}
            </button>
          </>
        )}
      </div>

      <p className="text-[11px] text-gray-500 font-semibold mb-4">
        Max {MAX_HIGHLIGHT_DURATION_SECONDS}s, {(MAX_HIGHLIGHT_BYTES / 1024 / 1024).toFixed(0)}MB.
      </p>

      {error && (
        <div className="mb-4 px-4 py-2.5 bg-red-500/10 border border-red-500/30 rounded-xl text-xs font-bold text-red-400">
          {error}
        </div>
      )}

      {highlights === null && (
        <div className="py-8 bg-[#1E293B]/30 border border-[#1E293B] rounded-2xl text-center">
          <Loader2 className="w-5 h-5 text-gray-400 animate-spin mx-auto" />
        </div>
      )}

      {highlights?.length === 0 && (
        <div className="py-8 bg-[#1E293B]/30 border border-[#1E293B] rounded-2xl text-center">
          <p className="text-sm font-bold text-gray-400">No highlights uploaded yet.</p>
        </div>
      )}

      {highlights && highlights.length > 0 && (
        <div className="space-y-3">
          {highlights.map((h) => (
            <HighlightTile
              key={h.id}
              highlight={h}
              teamName={h.teamId === match.homeTeamId ? homeTeamName : h.teamId === match.awayTeamId ? awayTeamName : 'Team'}
              onPlay={() => setPlayingUrl(h.secureUrl)}
            />
          ))}
        </div>
      )}

      {pendingFile && (
        <TeamPickerModal
          homeTeamId={match.homeTeamId}
          homeTeamName={homeTeamName}
          awayTeamId={match.awayTeamId}
          awayTeamName={awayTeamName}
          onPick={(teamId) => {
            const file = pendingFile;
            setPendingFile(null);
            if (file) void doUpload(file, teamId);
          }}
          onClose={() => setPendingFile(null)}
        />
      )}

      {playingUrl && <VideoModal url={playingUrl} onClose={() => setPlayingUrl(null)} />}
    </div>
  );
}

function HighlightTile({ highlight, teamName, onPlay }: { highlight: MatchHighlight; teamName: string; onPlay: () => void }) {
  const hasUrl = highlight.secureUrl.trim().length > 0;

  const statusLabel = isHighlightApproved(highlight)
    ? 'Approved'
    : isHighlightProcessing(highlight)
      ? 'Processing'
      : 'Uploading';
  const statusColor = isHighlightApproved(highlight)
    ? 'text-[#BEF264] bg-[#BEF264]/10 border-[#BEF264]/30'
    : isHighlightProcessing(highlight)
      ? 'text-amber-400 bg-amber-400/10 border-amber-400/30'
      : 'text-gray-400 bg-white/5 border-white/10';

  return (
    <button
      onClick={hasUrl ? onPlay : undefined}
      disabled={!hasUrl}
      className="w-full flex items-center gap-3 bg-[#1E293B]/30 border border-[#1E293B] rounded-xl p-3 text-left hover:border-sky-500/30 transition-colors disabled:cursor-default disabled:hover:border-[#1E293B]"
    >
      <div className="w-16 h-12 rounded-lg bg-[#1E293B] border border-white/5 flex items-center justify-center overflow-hidden shrink-0">
        {highlight.thumbnailUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={highlight.thumbnailUrl} alt="" className="w-full h-full object-cover" />
        ) : (
          <FileVideo className="w-5 h-5 text-gray-500" />
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-bold text-white truncate">{teamName}</p>
        <span className={`inline-block mt-1 px-2 py-0.5 rounded-full text-[10px] font-black border ${statusColor}`}>
          {statusLabel}
        </span>
      </div>
      {hasUrl ? (
        <PlayCircle className="w-6 h-6 text-sky-400 shrink-0" />
      ) : (
        <Loader2 className="w-5 h-5 text-gray-500 animate-spin shrink-0" />
      )}
    </button>
  );
}

function VideoModal({ url, onClose }: { url: string; onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="relative max-w-3xl w-full" onClick={(e) => e.stopPropagation()}>
        <button
          onClick={onClose}
          className="absolute -top-10 right-0 p-2 text-white/70 hover:text-white"
          aria-label="Close"
        >
          <X className="w-6 h-6" />
        </button>
        <video src={url} controls autoPlay className="w-full rounded-xl bg-black" />
      </div>
    </div>
  );
}

function TeamPickerModal({
  homeTeamId,
  homeTeamName,
  awayTeamId,
  awayTeamName,
  onPick,
  onClose,
}: {
  homeTeamId: string;
  homeTeamName: string;
  awayTeamId: string;
  awayTeamName: string;
  onPick: (teamId: string) => void;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-6 max-w-sm w-full"
        onClick={(e) => e.stopPropagation()}
      >
        <h4 className="text-sm font-black text-white mb-1">Which team is this highlight for?</h4>
        <p className="text-xs text-gray-400 mb-4">Choose the team this clip belongs to.</p>
        <div className="space-y-2">
          <button
            onClick={() => onPick(homeTeamId)}
            className="w-full py-3 bg-[#1E293B] hover:bg-[#2A3A52] rounded-xl text-sm font-bold text-white transition-colors"
          >
            {homeTeamName}
          </button>
          <button
            onClick={() => onPick(awayTeamId)}
            className="w-full py-3 bg-[#1E293B] hover:bg-[#2A3A52] rounded-xl text-sm font-bold text-white transition-colors"
          >
            {awayTeamName}
          </button>
        </div>
        <button onClick={onClose} className="w-full mt-4 py-2 text-xs font-bold text-gray-400 hover:text-white">
          Cancel
        </button>
      </div>
    </div>
  );
}
