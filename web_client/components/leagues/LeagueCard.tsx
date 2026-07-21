'use client';

import { useState, useRef, useEffect } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { MoreVertical, Crown, Eye, Trophy, Network, Lock } from 'lucide-react';
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
  if (leagueHasViewerCapacity(league)) pieces.push(`${league.viewerCapacity} viewers`);
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
      className={`group relative rounded-3xl border border-slate-100 dark:border-white/10 bg-white dark:bg-[#0F172A] shadow-[0_2px_12px_rgba(0,0,0,0.04)] hover:shadow-[0_8px_28px_rgba(0,0,0,0.08)] dark:shadow-none transition-all overflow-hidden ${
        removing ? 'opacity-50 pointer-events-none' : ''
      }`}
    >
      {/* ── CHANGED to onClick for instant single-tap navigation ── */}
      <div
        className="relative h-28 w-full cursor-pointer bg-gradient-to-br from-brand-lime/20 via-sky-100 to-white dark:from-brand-lime/10 dark:via-sky-900/20 dark:to-[#081120]"
        style={
          league.leagueImageUrl
            ? { backgroundImage: `url(${league.leagueImageUrl})`, backgroundSize: 'cover', backgroundPosition: 'center' }
            : undefined
        }
        onClick={onOpen}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => e.key === 'Enter' && onOpen()}
      >
        <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-black/0 to-black/0" />

        <div className="absolute top-3 right-3 flex flex-col items-end gap-1.5">
          {showMasterBadge && isInMaster && (
            <Badge icon={Network} label="MASTER" color="amber" />
          )}
          <Badge emoji={categoryEmoji(league.footballCategory)} label={categoryLabel(league.footballCategory)} color="lime" />
        </div>

        {isFull && (
          <div className="absolute top-3 left-3">
            <Badge icon={Lock} label="FULL" color="red" />
          </div>
        )}

        <div className="absolute bottom-3 left-3 right-3 flex items-end justify-between">
          <div className="min-w-0">
            <h3 className="text-white font-black text-base leading-tight truncate drop-shadow-md">
              {league.name}
            </h3>
            <p className="text-white/90 text-[11px] font-semibold truncate drop-shadow-md">
              {leagueFormatDisplayName(league.format)} • {league.season}
            </p>
          </div>

          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation(); // Stops the click from bubbling up and opening the league!
                setMenuOpen((v) => !v);
              }}
              className="w-8 h-8 shrink-0 rounded-full bg-black/40 hover:bg-black/60 backdrop-blur flex items-center justify-center text-white transition-colors"
              aria-label="League options"
            >
              <MoreVertical className="w-4 h-4" />
            </button>

            {menuOpen && (
              <div className="absolute right-0 top-10 z-10 w-52 bg-white dark:bg-[#0F172A] rounded-2xl shadow-xl border border-slate-100 dark:border-white/10 py-1.5 text-slate-800 dark:text-white" onClick={(e) => e.stopPropagation()}>
                {isOwner ? (
                  <div className="px-4 py-2.5 text-xs text-slate-400 dark:text-slate-500 font-semibold">
                    Manage this league from the Organizer area.
                  </div>
                ) : (
                  <button
                    type="button"
                    onClick={() => {
                      setMenuOpen(false);
                      onLeave();
                    }}
                    className="w-full text-left px-4 py-2.5 text-sm font-bold hover:bg-slate-50 dark:hover:bg-white/5 transition-colors"
                  >
                    Remove from my list
                  </button>
                )}
                {isInMaster && onOpenWorkspace && (
                  <button
                    type="button"
                    onClick={() => {
                      setMenuOpen(false);
                      onOpenWorkspace();
                    }}
                    className="w-full text-left px-4 py-2.5 text-sm font-bold hover:bg-slate-50 dark:hover:bg-white/5 transition-colors flex items-center gap-2"
                  >
                    <Network className="w-4 h-4 text-brand-lime" />
                    Open workspace
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="p-4 flex items-start gap-3">
        {/* QR Code */}
        <div className="shrink-0 bg-white p-1.5 rounded-xl border border-slate-100 dark:border-white/10 shadow-sm">
          <QRCodeSVG value={leagueQrPayload(league)} size={52} fgColor="#0F172A" level="M" />
        </div>

        <div className="min-w-0 flex-1">
          <p className="text-xs text-slate-500 dark:text-slate-400 font-semibold line-clamp-2 leading-relaxed">{subtitle}</p>

          <div className="mt-2 flex items-center gap-1.5 flex-wrap">
            <code className="text-[10px] font-black tracking-wide bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/10 rounded px-1.5 py-0.5 text-slate-500 dark:text-slate-400">
              {league.code || league.id.slice(0, 8)}
            </code>
            {isOwner && <InlineTag icon={Crown} label="Owner" color="text-red-500 bg-red-50 dark:bg-red-500/10" />}
            {!isOwner && isViewerOnly && <InlineTag icon={Eye} label="Viewer" color="text-slate-500 bg-slate-100 dark:text-slate-400 dark:bg-white/10" />}
          </div>
        </div>
      </div>

      <button
        type="button"
        onClick={onOpen}
        className="w-full py-2.5 text-xs font-black text-slate-500 dark:text-slate-400 border-t border-slate-100 dark:border-white/10 hover:bg-slate-50 dark:hover:bg-white/5 transition-colors flex items-center justify-center gap-1.5"
      >
        <Trophy className="w-3.5 h-3.5" />
        Open league
      </button>
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
  color: 'amber' | 'lime' | 'red';
  emoji?: string;
}) {
  const colorClasses = {
    amber: 'bg-amber-500/90 text-white',
    lime: 'bg-white/90 text-slate-900',
    red: 'bg-red-500/90 text-white',
  }[color];

  return (
    <span className={`flex items-center gap-1 px-2 py-1 rounded-lg text-[9px] font-black tracking-wide backdrop-blur ${colorClasses}`}>
      {Icon && <Icon className="w-3 h-3" />}
      {emoji && <span>{emoji}</span>}
      {label}
    </span>
  );
}

function InlineTag({
  icon: Icon,
  label,
  color,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  color: string;
}) {
  return (
    <span className={`flex items-center gap-1 px-1.5 py-0.5 rounded text-[9px] font-black ${color}`}>
      <Icon className="w-2.5 h-2.5" />
      {label}
    </span>
  );
}

export function LeagueCardSkeleton() {
  return (
    <div className="rounded-3xl border border-slate-100 dark:border-white/10 bg-white dark:bg-[#0F172A] overflow-hidden animate-pulse">
      <div className="h-28 bg-slate-100 dark:bg-white/5" />
      <div className="p-4 flex gap-3">
        <div className="w-[52px] h-[52px] rounded-xl bg-slate-100 dark:bg-white/5 shrink-0" />
        <div className="flex-1 space-y-2 pt-1">
          <div className="h-3 bg-slate-100 dark:bg-white/5 rounded w-3/4" />
          <div className="h-3 bg-slate-100 dark:bg-white/5 rounded w-1/2" />
        </div>
      </div>
    </div>
  );
}
