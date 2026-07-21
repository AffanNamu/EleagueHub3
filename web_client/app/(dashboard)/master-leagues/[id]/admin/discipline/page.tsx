'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import {
  Loader2,
  ArrowLeft,
  ShieldAlert,
  AlertOctagon,
  UserX,
  MessageSquareOff,
  Undo2,
  Gavel,
} from 'lucide-react';

export type DisciplineActionType =
  | 'warning'
  | 'points_deduction'
  | 'organizer_chat_mute'
  | 'organizer_chat_ban'
  | 'organizer_chat_unmute'
  | 'organizer_chat_unban';

interface DisciplineActionDoc {
  id: string;
  targetUserId: string;
  targetName: string;
  actionType: DisciplineActionType;
  pointsDelta: number;
  reason: string;
  createdBy: string;
  createdAtMs: number;
  active: boolean;
  reversedAtMs: number;
  reversalReason: string;
}

const ACTIONS: { id: DisciplineActionType; label: string; icon: any }[] = [
  { id: 'warning', label: 'Issue Warning', icon: AlertOctagon },
  { id: 'points_deduction', label: 'Deduct Points', icon: ShieldAlert },
  { id: 'organizer_chat_mute', label: 'Mute in Chat', icon: MessageSquareOff },
  { id: 'organizer_chat_ban', label: 'Ban from Hub', icon: UserX },
  { id: 'organizer_chat_unmute', label: 'Unmute', icon: MessageSquareOff },
  { id: 'organizer_chat_unban', label: 'Unban', icon: UserX },
];

export default function OrganizerDisciplineScreen() {
  const params = useParams();
  const router = useRouter();
  const masterLeagueId = params.id as string;

  const { workspace, loading: workspaceLoading, uid } = useMasterLeagueDetail(masterLeagueId);

  const [targetUserId, setTargetUserId] = useState('');
  const [targetName, setTargetName] = useState('');
  const [actionType, setActionType] = useState<DisciplineActionType>('warning');
  const [points, setPoints] = useState('1');
  const [reason, setReason] = useState('');

  const [history, setHistory] = useState<DisciplineActionDoc[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const isOwner = !!workspace && workspace.ownerId === uid;

  useEffect(() => {
    if (!masterLeagueId) return;
    const q = query(
      collection(db, 'master_leagues', masterLeagueId, 'disciplineActions'),
      orderBy('createdAtMs', 'desc'),
    );
    const unsub = onSnapshot(q, (snap) => {
      setHistory(
        snap.docs.map((d) => {
          const data = d.data();
          return {
            id: data.id ?? d.id,
            targetUserId: data.targetUserId ?? '',
            targetName: data.targetName ?? '',
            actionType: data.actionType,
            pointsDelta: Number(data.pointsDelta) || 0,
            reason: data.reason ?? '',
            createdBy: data.createdBy ?? '',
            createdAtMs: Number(data.createdAtMs) || 0,
            active: data.active === true,
            reversedAtMs: Number(data.reversedAtMs) || 0,
            reversalReason: data.reversalReason ?? '',
          } as DisciplineActionDoc;
        }),
      );
    });
    return () => unsub();
  }, [masterLeagueId]);

  if (workspaceLoading) {
    return (
      <div className="flex justify-center py-32">
        <Loader2 className="w-9 h-9 animate-spin text-[#38BDF8]" />
      </div>
    );
  }

  if (workspace && !isOwner) {
    return (
      <div className="max-w-md mx-auto flex flex-col items-center justify-center py-32 text-center">
        <div className="w-16 h-16 rounded-2xl bg-brand-red/10 border border-brand-red/25 flex items-center justify-center mb-4">
          <ShieldAlert className="w-8 h-8 text-brand-red" />
        </div>
        <h2 className="text-xl font-bold text-white">Access Denied</h2>
        <p className="text-sm text-gray-500 mt-1">Only the Hub Owner can access the discipline panel.</p>
        <button
          onClick={() => router.back()}
          className="mt-5 px-5 py-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-white text-sm font-bold hover:border-[#2A3A52] transition-colors"
        >
          Go Back
        </button>
      </div>
    );
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    const user = auth.currentUser;
    if (!user) return setError('Please sign in and try again.');
    if (!targetUserId.trim() || !reason.trim()) return setError('User ID and Reason are required.');

    const pointsNum = actionType === 'points_deduction' ? Math.abs(Number(points) || 0) : 0;
    if (actionType === 'points_deduction' && pointsNum <= 0) {
      return setError('Points must be greater than 0.');
    }

    setSaving(true);
    try {
      const actionRef = doc(collection(db, 'master_leagues', masterLeagueId, 'disciplineActions'));
      const moderationRef = doc(db, 'master_leagues', masterLeagueId, 'memberModeration', targetUserId.trim());
      const now = Date.now();

      await runTransaction(db, async (txn) => {
        const modSnap = await txn.get(moderationRef);
        const current = modSnap.exists()
          ? modSnap.data()
          : { points: 0, warnings: 0, chatMuted: false, chatBanned: false };

        let nextPoints = Number(current.points) || 0;
        let nextWarnings = Number(current.warnings) || 0;
        let nextMuted = current.chatMuted === true;
        let nextBanned = current.chatBanned === true;
        let pointsDelta = 0;

        switch (actionType) {
          case 'warning':
            nextWarnings += 1;
            break;
          case 'points_deduction':
            pointsDelta = -pointsNum;
            nextPoints += pointsDelta;
            break;
          case 'organizer_chat_mute':
            nextMuted = true;
            break;
          case 'organizer_chat_ban':
            nextBanned = true;
            nextMuted = true;
            break;
          case 'organizer_chat_unmute':
            nextMuted = false;
            break;
          case 'organizer_chat_unban':
            nextBanned = false;
            break;
        }

        txn.set(actionRef, {
          id: actionRef.id,
          masterLeagueId,
          targetUserId: targetUserId.trim(),
          targetName: targetName.trim(),
          targetRole: '',
          actionType,
          pointsDelta,
          reason: reason.trim(),
          createdBy: user.uid,
          createdAtMs: now,
          active: true,
          reversedAtMs: 0,
          reversedBy: '',
          reversalReason: '',
        });

        txn.set(
          moderationRef,
          {
            userId: targetUserId.trim(),
            displayName: targetName.trim(),
            points: nextPoints,
            warnings: nextWarnings,
            chatMuted: nextMuted,
            chatBanned: nextBanned,
            updatedAtMs: now,
          },
          { merge: true },
        );
      });

      setTargetUserId('');
      setTargetName('');
      setReason('');
      setPoints('1');
      setActionType('warning');
    } catch (err: any) {
      console.error(err);
      setError('Failed to apply action: ' + (err.message || String(err)));
    } finally {
      setSaving(false);
    }
  };

  const handleReverse = async (action: DisciplineActionDoc) => {
    if (action.reversedAtMs > 0) {
      alert('This action has already been reversed.');
      return;
    }
    const reversalReason = window.prompt('Reversal reason (required)');
    if (!reversalReason?.trim()) return;

    const user = auth.currentUser;
    if (!user) return;

    try {
      const actionRef = doc(db, 'master_leagues', masterLeagueId, 'disciplineActions', action.id);
      const moderationRef = doc(db, 'master_leagues', masterLeagueId, 'memberModeration', action.targetUserId);
      const now = Date.now();

      await runTransaction(db, async (txn) => {
        const modSnap = await txn.get(moderationRef);
        const current = modSnap.exists()
          ? modSnap.data()
          : { points: 0, warnings: 0, chatMuted: false, chatBanned: false };

        let nextPoints = Number(current.points) || 0;
        let nextWarnings = Number(current.warnings) || 0;
        let nextMuted = current.chatMuted === true;
        let nextBanned = current.chatBanned === true;

        switch (action.actionType) {
          case 'warning':
            if (nextWarnings > 0) nextWarnings -= 1;
            break;
          case 'points_deduction':
            nextPoints -= action.pointsDelta;
            break;
          case 'organizer_chat_mute':
            nextMuted = false;
            break;
          case 'organizer_chat_ban':
            nextBanned = false;
            break;
          case 'organizer_chat_unmute':
            nextMuted = true;
            break;
          case 'organizer_chat_unban':
            nextBanned = true;
            break;
        }

        txn.set(
          actionRef,
          { active: false, reversedAtMs: now, reversedBy: user.uid, reversalReason: reversalReason.trim() },
          { merge: true },
        );

        txn.set(
          moderationRef,
          {
            userId: action.targetUserId,
            points: nextPoints,
            warnings: nextWarnings,
            chatMuted: nextMuted,
            chatBanned: nextBanned,
            updatedAtMs: now,
          },
          { merge: true },
        );
      });
    } catch (e: any) {
      alert(e.message || 'Failed to reverse action.');
    }
  };

  return (
    <div className="max-w-3xl mx-auto pb-16 space-y-6">
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <div className="absolute -top-40 left-1/3 w-[450px] h-[450px] rounded-full bg-brand-red/[0.04] blur-[120px]" />
      </div>

      <div className="flex items-center gap-4">
        <button
          onClick={() => router.back()}
          className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-2">
            <Gavel className="w-6 h-6 text-brand-red" />
            Discipline Panel
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">Manage members and enforce community rules.</p>
        </div>
      </div>

      <PanelCard>
        {error && (
          <div className="p-3.5 bg-brand-red/10 text-brand-red border border-brand-red/30 rounded-xl mb-6 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-2">Target User ID</label>
            <input
              type="text"
              value={targetUserId}
              onChange={(e) => setTargetUserId(e.target.value)}
              required
              placeholder="Paste the user's UID here..."
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white font-mono text-sm placeholder:text-gray-600 focus:outline-none focus:border-brand-red/50 transition-colors"
            />
          </div>

          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-2">
              Target Display Name (optional)
            </label>
            <input
              type="text"
              value={targetName}
              onChange={(e) => setTargetName(e.target.value)}
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-sm text-white focus:outline-none focus:border-brand-red/50 transition-colors"
            />
          </div>

          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-3">Discipline Action</label>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {ACTIONS.map((action) => {
                const Icon = action.icon;
                const selected = actionType === action.id;
                return (
                  <button
                    key={action.id}
                    type="button"
                    onClick={() => setActionType(action.id)}
                    className={`flex items-center gap-3 p-3 rounded-xl border transition-colors text-left ${
                      selected
                        ? 'bg-brand-red/10 border-brand-red/40 text-brand-red'
                        : 'bg-[#070B14] border-[#1E293B] text-gray-400 hover:border-[#2A3A52]'
                    }`}
                  >
                    <Icon className="w-4.5 h-4.5" />
                    <span className="font-bold text-sm">{action.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {actionType === 'points_deduction' && (
            <div>
              <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-2">Points to Deduct</label>
              <input
                type="number"
                min={1}
                value={points}
                onChange={(e) => setPoints(e.target.value)}
                className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white focus:outline-none focus:border-brand-red/50 transition-colors"
              />
            </div>
          )}

          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-2">Reason / Justification</label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              required
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-white resize-none placeholder:text-gray-600 focus:outline-none focus:border-brand-red/50 transition-colors"
              placeholder="Describe the rule violation..."
            />
          </div>

          <div className="pt-4 border-t border-[#1E293B]">
            <button
              type="submit"
              disabled={saving}
              className="w-full py-3.5 bg-brand-red text-white font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-brand-red/20"
            >
              {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <ShieldAlert className="w-5 h-5" />}
              Enforce Action
            </button>
          </div>
        </form>
      </PanelCard>

      <PanelCard title="Discipline History" icon={<Gavel className="w-4 h-4 text-gray-500" />}>
        {history.length === 0 ? (
          <p className="text-sm text-gray-500 text-center py-4">No discipline actions yet.</p>
        ) : (
          <div className="space-y-3">
            {history.map((h) => (
              <div
                key={h.id}
                className="p-3.5 bg-[#070B14] border border-[#1E293B] rounded-xl flex items-start justify-between gap-3"
              >
                <div className="min-w-0">
                  <p className="text-sm font-bold text-white truncate">
                    {h.targetName || h.targetUserId} • {h.actionType.replace(/_/g, ' ')}
                  </p>
                  <p className="text-xs text-gray-500 mt-1 leading-relaxed">{h.reason}</p>
                  <p className="text-[10px] text-gray-600 mt-1.5">
                    {new Date(h.createdAtMs).toLocaleString()}
                    {h.reversedAtMs > 0 && <span className="text-amber-500 font-bold"> • Reversed</span>}
                  </p>
                </div>
                {h.reversedAtMs <= 0 && (
                  <button
                    onClick={() => handleReverse(h)}
                    className="shrink-0 flex items-center gap-1 text-xs font-bold text-gray-500 hover:text-white transition-colors"
                  >
                    <Undo2 className="w-3.5 h-3.5" /> Reverse
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </PanelCard>
    </div>
  );
}
