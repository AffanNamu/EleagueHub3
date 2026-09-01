'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useMasterLeagueDetails } from '@/hooks/useMasterLeagues';
import { applyDisciplineActionWeb } from '@/lib/masterLeagues/masterLeaguesRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Gavel, ShieldAlert } from 'lucide-react';

const ACTIONS = [
  { id: 'warning', label: 'Warning', points: 0, color: 'text-amber-500', bg: 'bg-amber-500' },
  { id: 'points_deduction', label: 'Deduct Points', points: -1, color: 'text-red-500', bg: 'bg-red-500' },
  { id: 'organizer_chat_mute', label: 'Mute Chat', points: 0, color: 'text-purple-500', bg: 'bg-purple-500' },
  { id: 'organizer_chat_ban', label: 'Ban Chat', points: 0, color: 'text-red-600', bg: 'bg-red-600' },
];

export default function OrganizerDisciplineScreen() {
  const params = useParams();
  const router = useRouter();
  const mlId = params.id as string;

  const { masterLeague, loading } = useMasterLeagueDetails(mlId);

  const [targetId, setTargetId] = useState('');
  const [reason, setReason] = useState('');
  const [actionType, setActionType] = useState('warning');
  const [pointsDelta, setPointsDelta] = useState(1);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-red-500" /></div>;
  if (!masterLeague || masterLeague.ownerId !== auth.currentUser?.uid) return <div className="text-center py-20 text-red-500 font-bold">Access Denied</div>;

  const handleSubmit = async () => {
    if (!targetId.trim() || !reason.trim()) return setError('Target ID and Reason are required.');
    
    setSubmitting(true);
    setError('');
    
    try {
      await applyDisciplineActionWeb({
        mlId,
        authUid: auth.currentUser!.uid,
        targetUserId: targetId.trim(),
        targetName: 'User', // In a real app, resolve this via repository
        targetRole: 'member',
        actionType,
        pointsDelta: actionType === 'points_deduction' ? -Math.abs(pointsDelta) : 0,
        reason: reason.trim()
      });
      alert('Discipline action applied successfully.');
      setTargetId(''); setReason('');
    } catch (err: any) {
      setError(err.message || 'Action failed.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl"><ArrowLeft className="w-5 h-5 text-white" /></button>
        <h1 className="text-xl md:text-2xl font-black text-red-500 flex items-center gap-2"><Gavel className="w-6 h-6" /> Discipline Panel</h1>
      </div>

      <Glass className="p-6 md:p-8 bg-[#0B1221] border-[#1E293B] rounded-3xl shadow-xl">
        {error && <div className="p-4 mb-6 bg-red-500/10 border border-red-500/30 text-red-500 rounded-xl text-sm font-bold flex gap-2"><ShieldAlert className="w-5 h-5"/>{error}</div>}

        <div className="space-y-5">
          <input placeholder="Target User ID (e.g. eS12345678)" value={targetId} onChange={e => setTargetId(e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-red-500 font-mono text-sm" />
          
          <div className="flex flex-wrap gap-2">
            {ACTIONS.map(a => (
              <button 
                key={a.id} onClick={() => setActionType(a.id)} 
                className={`px-4 py-2.5 rounded-xl text-xs font-black border transition-colors ${actionType === a.id ? `${a.bg}/20 ${a.color} border-${a.bg.split('-')[1]}-500/50` : 'bg-[#070B14] text-gray-500 border-[#1E293B]'}`}
              >
                {a.label}
              </button>
            ))}
          </div>

          {actionType === 'points_deduction' && (
            <input type="number" min="1" placeholder="Points to deduct" value={pointsDelta} onChange={e => setPointsDelta(parseInt(e.target.value)||1)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-red-500" />
          )}

          <textarea placeholder="Reason (Required for audit logs)" rows={3} value={reason} onChange={e => setReason(e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-red-500 resize-none" />

          <button onClick={handleSubmit} disabled={submitting} className="w-full py-4 mt-2 bg-red-600 text-white font-black rounded-xl hover:bg-red-500 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-red-600/20">
            {submitting ? <Loader2 className="w-5 h-5 animate-spin" /> : <Gavel className="w-5 h-5" />} Apply Action
          </button>
        </div>
      </Glass>
    </div>
  );
}
