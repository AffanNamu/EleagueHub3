'use client';

import React, { useState, useRef } from 'react';
import { UploadCloud, Loader2, AlertTriangle, X, Verified, CloudOff, Hourglass, WifiOff, FileText, CheckCircle2 } from 'lucide-react';
import { Glass } from '@/components/ui/Glass';
import { doc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { resolveTeamParticipant } from '@/lib/services/userProfileRepository';
import { motion, AnimatePresence } from 'framer-motion';

export interface CsvImporterProps {
  leagueId: string;
  isGroupFormat: boolean;
  allowedGroups: string[];
  onSuccess: () => void;
}

type RosterRowStatus = 'pending' | 'ok' | 'okCsv' | 'notFound' | 'offline';

interface ResolvedRosterProfile {
  userId: string;
  teamName: string;
}

interface RosterCsvRow {
  input: string;
  teamNameFromCsv: string | null;
  group: string | null;
  resolved: ResolvedRosterProfile | null;
  status: RosterRowStatus;
}

function looksLikeShareId(input: string) {
  return input.trim().startsWith('eS');
}

function looksLikeFirebaseUid(input: string) {
  const t = input.trim();
  if (t.length === 0) return false;
  if (looksLikeShareId(t)) return false;
  return t.length > 20;
}

function displayInput(raw: string) {
  const t = raw.trim();
  if (looksLikeFirebaseUid(t)) return 'Firebase UID (hidden)';
  return t;
}

export const CsvImporter: React.FC<CsvImporterProps> = ({ leagueId, isGroupFormat, allowedGroups, onSuccess }) => {
  const [loadingFile, setLoadingFile] = useState(false);
  const [error, setError] = useState('');
  const [filename, setFilename] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [rows, setRows] = useState<RosterCsvRow[]>([]);
  const [validating, setValidating] = useState(false);
  const [saving, setSaving] = useState(false);

  // ── CSV Parsing Logic (Directly from Dart) ──────────────────────────────────
  const splitCsvLine = (line: string) => {
    const out: string[] = [];
    let buf = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] === '"') {
          buf += '"';
          i++;
          continue;
        }
        inQuotes = !inQuotes;
        continue;
      }
      if (ch === ',' && !inQuotes) {
        out.push(buf);
        buf = '';
        continue;
      }
      buf += ch;
    }
    out.push(buf);
    return out;
  };

  const normalizeGroup = (raw: string, allowed: string[]) => {
    const t = raw.trim();
    if (!t) return null;
    if (allowed.includes(t)) return t;

    const upper = t.toUpperCase();
    if (upper.length === 1 && /^[A-H]$/.test(upper)) {
      const candidate = `Group ${upper}`;
      if (allowed.includes(candidate)) return candidate;
    }

    const compact = upper.replace(/\s+/g, '');
    if (compact.startsWith('GROUP') && compact.length === 6) {
      const letter = compact.substring(5, 6);
      const candidate = `Group ${letter}`;
      if (allowed.includes(candidate)) return candidate;
    }
    return null;
  };

  const parseRosterCsv = (csvText: string) => {
    const lines = csvText.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) return [];

    const first = splitCsvLine(lines[0]).map(e => e.trim());
    let hasHeader = false;
    let idIdx = 0;
    let groupIdx: number | null = null;
    let teamNameIdx: number | null = null;

    if (first.length > 0) {
      const lowered = first.map(e => e.toLowerCase().replace(/\s+/g, ''));
      const idCandidates = ['userid', 'user_id', 'useridorshareid', 'useridor_shareid', 'user_id_or_share_id', 'useridorshare', 'shareid', 'share_id'];
      const groupCandidates = ['group', 'groupid', 'group_id'];
      const teamNameCandidates = ['teamname', 'team_name'];

      const foundId = lowered.findIndex(c => idCandidates.includes(c));
      if (foundId >= 0) { hasHeader = true; idIdx = foundId; }

      const foundGroup = lowered.findIndex(c => groupCandidates.includes(c));
      if (foundGroup >= 0) { hasHeader = true; groupIdx = foundGroup; }

      const foundTeam = lowered.findIndex(c => teamNameCandidates.includes(c));
      if (foundTeam >= 0) { hasHeader = true; teamNameIdx = foundTeam; }
    }

    const dataLines = hasHeader ? lines.slice(1) : lines;
    const out: RosterCsvRow[] = [];

    for (const line of dataLines) {
      const cols = splitCsvLine(line);
      if (cols.length === 0) continue;

      const id = idIdx < cols.length ? cols[idIdx].trim() : '';
      if (!id) continue;

      let group: string | null = null;
      if (isGroupFormat && groupIdx !== null && groupIdx < cols.length) {
        group = normalizeGroup(cols[groupIdx], allowedGroups);
      }

      let teamNameFromCsv: string | null = null;
      if (teamNameIdx !== null && teamNameIdx < cols.length) {
        const t = cols[teamNameIdx].trim();
        if (t) teamNameFromCsv = t;
      }

      out.push({
        input: id,
        teamNameFromCsv,
        group,
        resolved: null,
        status: 'pending',
      });
    }
    return out;
  };

  // ── Actions ────────────────────────────────────────────────────────────────
  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    
    setError('');
    setLoadingFile(true);
    setFilename(file.name);

    try {
      const text = await file.text();
      const parsedRows = parseRosterCsv(text);
      if (parsedRows.length === 0) throw new Error("No rows found in CSV.");
      
      setRows(parsedRows);
      setIsModalOpen(true);
    } catch (err: any) {
      setError(`CSV import failed: ${err.message}`);
    } finally {
      setLoadingFile(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const validateNow = async () => {
    setValidating(true);
    setError('');

    try {
      const updated = await Promise.all(rows.map(async (r) => {
        const input = r.input.trim();
        const csvName = r.teamNameFromCsv?.trim();
        const canFallbackToCsv = !looksLikeShareId(input) && !!csvName;

        try {
          const profile = await resolveTeamParticipant(input);
          if (profile) {
            return { ...r, resolved: { userId: profile.userId, teamName: profile.teamName }, status: 'ok' as RosterRowStatus };
          }
          if (canFallbackToCsv) {
            return { ...r, resolved: { userId: input, teamName: csvName as string }, status: 'okCsv' as RosterRowStatus };
          }
          return { ...r, resolved: null, status: 'notFound' as RosterRowStatus };
        } catch (e) {
          if (canFallbackToCsv) {
            return { ...r, resolved: { userId: input, teamName: csvName as string }, status: 'okCsv' as RosterRowStatus };
          }
          return { ...r, resolved: null, status: 'offline' as RosterRowStatus };
        }
      }));
      setRows(updated);
    } catch (e: any) {
      setError(`Validation failed: ${e.message}`);
    } finally {
      setValidating(false);
    }
  };

  const addValidAndClose = async () => {
    const valid = rows.filter(r => (r.status === 'ok' || r.status === 'okCsv') && r.resolved);
    if (valid.length === 0) return;

    setSaving(true);
    try {
      const batch = writeBatch(db);
      const now = Date.now();

      for (const r of valid) {
        const { userId, teamName } = r.resolved!;
        const teamRef = doc(db, 'leagues', leagueId, 'teams', userId);
        batch.set(teamRef, {
          id: userId,
          leagueId,
          name: teamName,
          ownerId: userId,
          groupId: isGroupFormat ? r.group || null : null,
          played: 0, won: 0, drawn: 0, lost: 0,
          goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
          basePoints: 0, adminAdjustment: 0, finalPoints: 0,
          updatedAtMs: now,
        }, { merge: true });
      }

      await batch.commit();
      setIsModalOpen(false);
      onSuccess();
    } catch (e: any) {
      setError(`Failed to save teams: ${e.message}`);
    } finally {
      setSaving(false);
    }
  };

  // Stats for the UI
  const okCount = rows.filter(r => r.status === 'ok').length;
  const okCsvCount = rows.filter(r => r.status === 'okCsv').length;
  const notFoundCount = rows.filter(r => r.status === 'notFound').length;
  const offlineCount = rows.filter(r => r.status === 'offline').length;
  const totalValid = okCount + okCsvCount;

  return (
    <>
      <Glass className="p-6">
        <h2 className="text-lg font-bold text-white mb-1">Bulk Import Roster</h2>
        <p className="text-xs text-gray-400 mb-4">Upload a CSV file containing participant UIDs to preview and validate them.</p>

        {error && !isModalOpen && (
          <div className="text-xs text-brand-red mb-4 flex items-start gap-2 bg-brand-red/10 border border-brand-red/20 rounded-lg p-3">
            <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" /> {error}
          </div>
        )}

        <div className="relative">
          <input type="file" accept=".csv" onChange={handleFileUpload} ref={fileInputRef} className="hidden" />
          <button 
            onClick={() => fileInputRef.current?.click()}
            disabled={loadingFile}
            className="w-full py-3 bg-brand-surface border border-white/10 text-white font-bold rounded-lg hover:bg-white/5 hover:border-brand-lime/50 transition-all disabled:opacity-50 flex items-center justify-center gap-2 text-sm"
          >
            {loadingFile ? <Loader2 className="w-4 h-4 animate-spin" /> : <UploadCloud className="w-4 h-4" />}
            {loadingFile ? 'Reading...' : 'Upload CSV File'}
          </button>
        </div>
        <p className="text-[10px] text-gray-500 mt-3 text-center">Format: <code className="bg-black/30 px-1 py-0.5 rounded">userId, teamName, group</code></p>
      </Glass>

      <AnimatePresence>
        {isModalOpen && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="w-full max-w-2xl bg-[#0F172A] border border-white/10 rounded-[28px] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
            >
              <div className="p-6 border-b border-white/5">
                <div className="flex items-center gap-4">
                  <div className="w-11 h-11 rounded-full bg-brand-lime/10 flex items-center justify-center">
                    <FileText className="w-5 h-5 text-brand-lime" />
                  </div>
                  <div className="flex-1">
                    <h2 className="text-lg font-black text-white">Import Roster Preview</h2>
                    <p className="text-xs font-semibold text-slate-400 truncate">{filename}</p>
                  </div>
                  <button onClick={() => setIsModalOpen(false)} className="p-2 text-slate-400 hover:text-white bg-white/5 rounded-full transition-colors">
                    <X className="w-5 h-5" />
                  </button>
                </div>

                <div className="flex flex-wrap gap-2 mt-5">
                  <StatusChip icon={FileText} label={`${rows.length} Rows`} color="text-slate-400" bg="bg-white/5" border="border-white/10" />
                  <StatusChip icon={Verified} label={`${okCount} OK`} color="text-green-400" bg="bg-green-500/10" border="border-green-500/20" />
                  <StatusChip icon={CloudOff} label={`${okCsvCount} CSV`} color="text-brand-lime" bg="bg-brand-lime/10" border="border-brand-lime/20" />
                  {notFoundCount > 0 && <StatusChip icon={X} label={`${notFoundCount} Missing`} color="text-red-400" bg="bg-red-500/10" border="border-red-500/20" />}
                  {offlineCount > 0 && <StatusChip icon={WifiOff} label={`${offlineCount} Offline`} color="text-amber-400" bg="bg-amber-500/10" border="border-amber-500/20" />}
                </div>

                <div className="flex gap-3 mt-4">
                  <button 
                    onClick={validateNow} disabled={validating || saving}
                    className="flex-1 py-2.5 bg-brand-lime/10 text-brand-lime font-bold rounded-xl border border-brand-lime/30 flex items-center justify-center gap-2 hover:bg-brand-lime/20 transition-colors disabled:opacity-50"
                  >
                    {validating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Verified className="w-4 h-4" />} Validate
                  </button>
                </div>
                
                {error && (
                  <div className="mt-4 text-xs text-red-400 flex items-start gap-2 bg-red-500/10 border border-red-500/20 rounded-lg p-3">
                    <AlertTriangle className="w-4 h-4 shrink-0" /> {error}
                  </div>
                )}
              </div>

              <div className="flex-1 overflow-y-auto p-6 space-y-2 bg-[#081120]">
                {rows.map((row, idx) => (
                  <RowCard key={idx} row={row} isGroupLeague={isGroupFormat} />
                ))}
              </div>

              <div className="p-6 border-t border-white/5 bg-[#0F172A]">
                <button 
                  onClick={addValidAndClose}
                  disabled={validating || saving || totalValid === 0}
                  className="w-full py-3.5 bg-brand-lime text-[#081120] font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <CheckCircle2 className="w-5 h-5" />}
                  {saving ? 'Adding Teams...' : `Add valid (${totalValid}) to roster`}
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </>
  );
};

// ── UI Helpers ──────────────────────────────────────────────────────────────
function StatusChip({ icon: Icon, label, color, bg, border }: any) {
  return (
    <div className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg border ${bg} ${border}`}>
      <Icon className={`w-3.5 h-3.5 ${color}`} />
      <span className={`text-[11px] font-black tracking-wide ${color}`}>{label}</span>
    </div>
  );
}

function RowCard({ row, isGroupLeague }: { row: RosterCsvRow, isGroupLeague: boolean }) {
  const isOk = row.status === 'ok';
  const isOkCsv = row.status === 'okCsv';
  const isPending = row.status === 'pending';
  const isOffline = row.status === 'offline';

  const rawInput = row.input.trim();
  const displayed = displayInput(rawInput);
  const isHiddenUid = displayed !== rawInput;

  let IconComp = X;
  let colorClass = "text-red-400";
  let bgClass = "bg-red-500/10";
  let title = displayed;
  let subtitle = "No profile found";

  if (isOk) {
    IconComp = Verified;
    colorClass = "text-green-400";
    bgClass = "bg-green-500/10";
    title = row.resolved!.teamName;
    subtitle = isHiddenUid ? 'Verified • UID hidden' : `Verified • ${displayed}`;
  } else if (isOkCsv) {
    IconComp = CloudOff;
    colorClass = "text-brand-lime";
    bgClass = "bg-brand-lime/10";
    title = row.resolved!.teamName;
    subtitle = isHiddenUid ? 'CSV OK • UID hidden' : `CSV OK • ${displayed}`;
  } else if (isPending) {
    IconComp = Hourglass;
    colorClass = "text-slate-400";
    bgClass = "bg-white/5";
    subtitle = "Pending validation";
  } else if (isOffline) {
    IconComp = WifiOff;
    colorClass = "text-amber-400";
    bgClass = "bg-amber-500/10";
    subtitle = "Offline (cannot verify)";
  }

  return (
    <div className="flex items-center gap-3 p-3 rounded-xl bg-white/5 border border-white/5">
      <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${bgClass}`}>
        <IconComp className={`w-4 h-4 ${colorClass}`} />
      </div>
      <div className="flex-1 min-w-0">
        <h4 className="text-sm font-bold text-white truncate">{title}</h4>
        <p className="text-[11px] text-slate-400 truncate">{subtitle}</p>
      </div>
      {isGroupLeague && (
        <div className="px-2 py-1 bg-white/5 border border-white/10 rounded-md">
          <span className="text-[10px] font-bold text-slate-400">{row.group || '—'}</span>
        </div>
      )}
    </div>
  );
}
