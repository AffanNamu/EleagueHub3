'use client';

import { useState, useRef, useEffect } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { MoreVertical, ShieldCheck, Eye, Trophy, Network, Lock, Crown, Touchpad } from 'lucide-react';
import {
  LeagueData,
  leagueQrPayload,
  leagueIsInsideMasterLeague,
  leagueHasViewerCapacity,
} from '@/lib/models/league';
import { leagueFormatDisplayName } from '@/lib/models/leagueFormat';
import { categoryEmoji, categoryLabel } from '@/lib/models/footballCategory';
import { LatestAnnouncement } from '@/lib/leagues/leaguesRepository';

export interface LeagueCardProps {
  league: LeagueData;
  registered: number;
  isOwner: boolean;
  isViewerOnly: boolean;
  latestAnnouncement: LatestAnnouncement | null;
  showMasterBadge: boolean;
  onOpen: () => void;
  onLeave: () => void;
  onOpenWorkspace?: () => void;
  removing?: boolean;
}

function buildSubtitle(
  league: LeagueData,
  registered: number,
  latestAnnouncement: LatestAnnouncement | null,
): string {
  const pieces: string[] = [`${registered} / ${league.maxTeams} teams`];
  if (leagueHasViewerCapacity(league)) pieces.push(`${league.viewerCapacity} Viewers`);
  if (league.description.trim()) pieces.push(league.description.trim());
  if (latestAnnouncement?.title.trim()) pieces.push(latestAnnouncement.title.trim());
  return pieces.join(' • ');
}

export function LeagueCard({
  league,
  registered,
  isOwner,
  isViewerOnly,
  latestAnnouncement,
  showMasterBadge,
  onOpen,
  onLeave,
  onOpenWorkspace,
  removing,
}: LeagueCardProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!menuOpen) return;
    const onClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, [menuOpen]);

  const isFull = registered >= league.maxTeams;
  const subtitle = buildSubtitle(league, registered, latestAnnouncement);
  const isInMaster = leagueIsInsideMasterLeague(league);

  return (
    <div
      className={`group relative rounded-[28px] border border-[#1E293B] bg-[#0B1221] shadow-xl shadow-black/10 hover:border-white/10 transition-all overflow-hidden flex flex-col ${
        removing ? 'opacity-60 pointer-events-none' : ''
      }`}
    >
      {/* ── IMAGE BANNER & TOP BADGES ── */}
      <div
        className="relative h-36 w-full cursor-pointer bg-gradient-to-br from-[#BEF264]/10 via-[#0B1221] to-[#070B14] shrink-0"
        style={
          league.leagueImageUrl
            ? { backgroundImage: `url(${league.leagueImageUrl})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : undefined
        }
        onClick={onOpen}
      >
        <div className="absolute inset-0 bg-gradient-to-t from-[#0B1221] via-black/20 to-black/40" />

        {/* Top Badges (Match Flutter exactly) */}
        <div className="absolute top-3 right-3 flex flex-col items-end gap-1.5">
          {showMasterBadge && isInMaster && (
            <Badge icon={Network} label="MASTER" color="amber" />
          )}
          <Badge emoji={categoryEmoji(league.footballCategory)} label={categoryLabel(league.footballCategory)} color="lime" />
          
          {isOwner && (
            <Badge icon={ShieldCheck} label="OWNER" color="red" />
          )}
          {!isOwner && isViewerOnly && (
            <Badge icon={Eye} label="VIEWER" color="slate" />
          )}
        </div>

        {/* Full Badge (Top Left) */}
        {isFull && (
          <div className="absolute top-3 left-3">
            <Badge icon={Lock} label="FULL" color="red" />
          </div>
        )}

        {/* Bottom Title & Options */}
        <div className="absolute bottom-3 left-4 right-3 flex items-end justify-between">
          <div className="min-w-0 pr-2">
            <h3 className="text-white font-black text-lg leading-tight truncate drop-shadow-lg">
              {league.name}
            </h3>
            <p className="text-white/80 text-xs font-bold truncate mt-0.5 drop-shadow-md">
              {leagueFormatDisplayName(league.format)} • {league.season}
            </p>
          </div>

          <div className="relative shrink-0" ref={menuRef}>
            <button
              onClick={(e) => {
                e.stopPropagation();
                setMenuOpen((v) => !v);
              }}
              className="w-8 h-8 rounded-full bg-black/50 hover:bg-[#BEF264] hover:text-[#0F172A] backdrop-blur flex items-center justify-center text-white transition-all shadow-md"
              aria-label="League options"
            >
              <MoreVertical className="w-4 h-4" />
            </button>

            {menuOpen && (
              <div className="absolute right-0 top-10 z-20 w-56 bg-[#1E293B] rounded-2xl shadow-2xl border border-white/10 py-1.5 text-white" onClick={(e) => e.stopPropagation()}>
                {isOwner ? (
                  <div className="px-4 py-3 text-xs text-gray-400 font-bold leading-relaxed">
                    League owners should manage their league from the owner/admin area.
                  </div>
                ) : (
                  <button
                    onClick={() => { setMenuOpen(false); onLeave(); }}
                    className="w-full text-left px-4 py-3 text-sm font-bold hover:bg-white/5 transition-colors flex items-center gap-2"
                  >
                    <Touchpad className="w-4 h-4 text-gray-400" />
                    Remove from My List
                  </button>
                )}
                {isInMaster && onOpenWorkspace && (
                  <>
                    <div className="h-px bg-white/10 my-1 mx-3" />
                    <button
                      onClick={() => { setMenuOpen(false); onOpenWorkspace(); }}
                      className="w-full text-left px-4 py-3 text-sm font-bold hover:bg-white/5 transition-colors flex items-center gap-2"
                    >
                      <Network className="w-4 h-4 text-[#BEF264]" />
                      Open Workspace
                    </button>
                  </>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ── LOWER SECTION ── */}
      <div className="p-4 flex flex-col flex-1 bg-[#0B1221]">
        <div className="flex items-start gap-4 mb-4 flex-1">
          {/* QR Code */}
          <div className="shrink-0 bg-white p-1.5 rounded-2xl border-4 border-[#1E293B] shadow-md">
            <QRCodeSVG value={leagueQrPayload(league)} size={56} fgColor="#0F172A" level="M" />
          </div>

          <div className="min-w-0 flex-1">
            <p className="text-xs text-gray-400 font-semibold line-clamp-3 leading-relaxed">
              {subtitle}
            </p>
            <div className="mt-3">
              <code className="text-[10px] font-black tracking-widest bg-[#1E293B] border border-white/5 rounded-md px-2 py-1 text-white">
                {league.code || league.id.slice(0, 8)}
              </code>
            </div>
          </div>
        </div>

        {/* Open Button matching Mobile App */}
        <button
          onClick={onOpen}
          className="w-full py-3 bg-[#1E293B]/50 hover:bg-[#1E293B] text-white text-xs font-black rounded-xl transition-colors flex items-center justify-center gap-2"
        >
          <Trophy className="w-4 h-4 text-[#BEF264]" />
          Open League
        </button>
      </div>
    </div>
  );
}

function Badge({
  icon: Icon,
  label,
  color,
  emoji,
}: {
  icon?: React.ComponentType<{ className?: string }>;
  label?: string;
  color: 'amber' | 'lime' | 'red' | 'slate';
  emoji?: string;
}) {
  const colorClasses = {
    amber: 'bg-amber-500/10 border-amber-500/40 text-amber-500',
    lime: 'bg-[#BEF264]/10 border-[#BEF264]/40 text-[#BEF264]',
    red: 'bg-red-500/10 border-red-500/40 text-red-500',
    slate: 'bg-slate-500/10 border-slate-500/40 text-gray-400',
  }[color];

  return (
    <span className={`flex items-center gap-1.5 px-2 py-1 rounded-lg text-[9px] font-black tracking-widest uppercase border backdrop-blur-md ${colorClasses}`}>
      {Icon && <Icon className="w-3 h-3" />}
      {emoji && <span className="text-sm leading-none">{emoji}</span>}
      {label}
    </span>
  );
}

export function LeagueCardSkeleton() {
  return (
    <div className="rounded-[28px] border border-[#1E293B] bg-[#0B1221] overflow-hidden animate-pulse flex flex-col h-full">
      <div className="h-36 bg-[#1E293B]/50 w-full" />
      <div className="p-4 flex flex-col flex-1">
        <div className="flex gap-4 mb-4">
          <div className="w-[72px] h-[72px] rounded-2xl bg-[#1E293B]/50 shrink-0" />
          <div className="flex-1 space-y-3 pt-2">
            <div className="h-2.5 bg-[#1E293B] rounded-full w-full" />
            <div className="h-2.5 bg-[#1E293B] rounded-full w-2/3" />
          </div>
        </div>
        <div className="h-10 bg-[#1E293B]/50 rounded-xl w-full mt-auto" />
      </div>
    </div>
  );
}
