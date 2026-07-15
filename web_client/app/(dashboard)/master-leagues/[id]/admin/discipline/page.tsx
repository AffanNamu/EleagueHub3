'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { collection, doc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, ShieldAlert, AlertOctagon, UserX, MessageSquareOff } from 'lucide-react';

export type DisciplineActionType = 
  | 'warning' 
  | 'points_deduction' 
  | 'organizer_chat_mute' 
  | 'organizer_chat_ban' 
  | 'organizer_chat_unmute' 
  | 'organizer_chat_unban';

export default function OrganizerDisciplineScreen() {
  const params = useParams();
  const router = useRouter();
  const masterLeagueId = params.id as string;

  const { workspace, loading: workspaceLoading } = useMasterLeagueDetail(masterLeagueId);

  const [targetUserId, setTargetUserId] = useState('');
  const [actionType, setActionType] = useState<DisciplineActionType>('warning');
  const [reason, setReason] = useState('');
  
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Security Check: Only the Master League owner can access this
  if (workspace && auth.currentUser?.uid !== workspace.ownerId) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-brand-red">
        <ShieldAlert className="w-16 h-16 mb-4" />
        <h2 className="text-xl font-bold">Access Denied</h2>
        <p>Only the Hub Owner can access the discipline panel.</p>
        <button onClick={() => router.back()} className="mt-4 px-4 py-2 bg-brand-surface rounded-lg text-white">Go Back</button>
      </div>
    );
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!targetUserId.trim() || !reason.trim()) {
      setError('User ID and Reason are required.');
      return;
    }

    setSaving(true);
    setError('');

    try {
      // 1. Log the discipline action
      const actionRef = doc(collection(db, 'master_leagues', masterLeagueId, 'discipline_actions'));
      await setDoc(actionRef, {
        id: actionRef.id,
        masterLeagueId,
        targetUserId: targetUserId.trim(),
        actionType,
        reason: reason.trim(),
        issuedBy: auth.currentUser?.uid,
        createdAt: serverTimestamp(),
        createdAtMs: Date.now(),
      });

      // 2. Apply chat restrictions if applicable (mirrors Dart backend sync)
      const followerRef = doc(db, 'master_leagues', masterLeagueId, 'followers', targetUserId.trim());
      
      if (actionType === 'organizer_chat_mute') {
        await updateDoc(followerRef, { chatMuted: true, updatedAtMs: Date.now() }).catch(() => {});
      } else if (actionType === 'organizer_chat_ban') {
        await updateDoc(followerRef, { chatBanned: true, updatedAtMs: Date.now() }).catch(() => {});
      } else if (actionType === 'organizer_chat_unmute') {
        await updateDoc(followerRef, { chatMuted: false, updatedAtMs: Date.now() }).catch(() => {});
      } else if (actionType === 'organizer_chat_unban') {
        await updateDoc(followerRef, { chatBanned: false, updatedAtMs: Date.now() }).catch(() => {});
      }

      alert("Discipline action applied successfully.");
      setTargetUserId('');
      setReason('');
    } catch (err: any) {
      console.error(err);
      setError('Failed to apply action: ' + err.message);
    } finally {
      setSaving(false);
    }
  };

  if (workspaceLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#38BDF8]" /></div>;

  return (
    <div className="space-y-6 max-w-3xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-brand-red flex items-center gap-2">
            <ShieldAlert className="w-6 h-6" />
            Discipline Panel
          </h1>
          <p className="text-gray-400 mt-1">Manage followers and enforce community rules.</p>
        </div>
      </div>

      <Glass className="p-6 md:p-8">
        {error && <div className="p-3 bg-brand-red/20 text-brand-red border border-brand-red rounded-lg mb-6 text-sm">{error}</div>}

        <form onSubmit={handleSubmit} className="space-y-6">
          
          {/* Target User */}
          <div>
            <label className="block text-sm font-bold text-gray-300 mb-1">Target User ID</label>
            <input 
              type="text" 
              value={targetUserId} 
              onChange={(e) => setTargetUserId(e.target.value)} 
              required 
              placeholder="Paste the user's UID here..."
              className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-red font-mono text-sm" 
            />
            <p className="text-xs text-gray-500 mt-1">In a full production build, this would be a searchable dropdown.</p>
          </div>

          {/* Action Type */}
          <div>
            <label className="block text-sm font-bold text-gray-300 mb-3">Discipline Action</label>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {[
                { id: 'warning', label: 'Issue Warning', icon: AlertOctagon },
                { id: 'points_deduction', label: 'Deduct Points', icon: ShieldAlert },
                { id: 'organizer_chat_mute', label: 'Mute in Chat', icon: MessageSquareOff },
                { id: 'organizer_chat_ban', label: 'Ban from Hub', icon: UserX },
                { id: 'organizer_chat_unmute', label: 'Unmute', icon: MessageSquareOff },
                { id: 'organizer_chat_unban', label: 'Unban', icon: UserX },
              ].map((action) => {
                const Icon = action.icon;
                const isSelected = actionType === action.id;
                return (
                  <button
                    key={action.id}
                    type="button"
                    onClick={() => setActionType(action.id as DisciplineActionType)}
                    className={`flex items-center gap-3 p-3 rounded-xl border transition-colors ${
                      isSelected 
                        ? 'bg-brand-red/10 border-brand-red text-brand-red' 
                        : 'bg-brand-surface border-white/5 text-gray-400 hover:bg-white/5'
                    }`}
                  >
                    <Icon className="w-5 h-5" />
                    <span className="font-bold text-sm">{action.label}</span>
                  </button>
                )
              })}
            </div>
          </div>

          {/* Reason */}
          <div>
            <label className="block text-sm font-bold text-gray-300 mb-1">Reason / Justification</label>
            <textarea 
              value={reason} 
              onChange={(e) => setReason(e.target.value)} 
              rows={3} 
              required
              className="w-full bg-brand-surface border border-white/10 rounded-xl p-3 text-white focus:border-brand-red resize-none" 
              placeholder="Describe the rule violation..." 
            />
          </div>

          <div className="pt-4 border-t border-white/5">
            <button 
              type="submit" 
              disabled={saving} 
              className="w-full py-4 bg-brand-red text-white font-black rounded-xl hover:bg-brand-red/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
            >
              {saving ? <Loader2 className="w-5 h-5 animate-spin" /> : <ShieldAlert className="w-5 h-5" />} 
              Enforce Action
            </button>
          </div>
        </form>
      </Glass>
    </div>
  );
}
