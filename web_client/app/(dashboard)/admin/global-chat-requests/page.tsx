'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { collection, query, where, limit, onSnapshot } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { updateGlobalChatRequestStatusWeb } from '@/lib/chat/chatRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, CheckCircle, XCircle, ShieldAlert, Copy } from 'lucide-react';

export default function GlobalChatAdminRequestsScreen() {
  const router = useRouter();
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [processingId, setProcessingId] = useState<string | null>(null);
  
  const [authUid, setAuthUid] = useState<string | null>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged(u => setAuthUid(u?.uid || null));
    return () => unsub();
  }, []);

  useEffect(() => {
    if (authUid !== 'QhYeBpvAoRV6j0xGigHkBth4qIG3') {
      setLoading(false);
      return;
    }

    const q = query(collection(db, 'globalChatRequests'), where('status', '==', 'pending'), limit(200));
    const unsub = onSnapshot(q, (snap) => {
      // FIXED: Explicitly cast to 'any' so TypeScript allows sorting by createdAtMs
      setRequests(snap.docs.map(d => ({ id: d.id, ...d.data() } as any)).sort((a: any, b: any) => b.createdAtMs - a.createdAtMs));
      setLoading(false);
    });
    return () => unsub();
  }, [authUid]);

  const handleUpdateStatus = async (id: string, status: 'approved' | 'rejected') => {
    if (processingId) return;
    setProcessingId(id);
    try {
      await updateGlobalChatRequestStatusWeb(id, status);
    } catch (err) {
      alert("Update failed");
    } finally {
      setProcessingId(null);
    }
  };

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;
  if (authUid !== 'a0JDUelQW3TEyoXTm4ESuGi7ndq1') return <div className="text-center py-20 text-red-500 font-bold">Super Admin Access Required</div>;

  return (
    <div className="max-w-4xl mx-auto space-y-6 pb-20 px-4 mt-6">
      <div className="flex items-center gap-4 mb-6">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl"><ArrowLeft className="w-5 h-5 text-white" /></button>
        <h1 className="text-2xl font-black text-white flex items-center gap-2"><ShieldAlert className="w-6 h-6 text-amber-500"/> Pending Requests</h1>
      </div>

      <Glass className="p-6 bg-[#0B1221] border-[#1E293B] rounded-3xl mb-8 flex items-center gap-4">
        <div className="w-12 h-12 rounded-full bg-amber-500/10 border border-amber-500/30 flex items-center justify-center shrink-0">
          <ShieldAlert className="w-6 h-6 text-amber-500" />
        </div>
        <div>
          <p className="text-white font-black text-lg">{requests.length} requests pending</p>
          <p className="text-xs text-gray-400 font-semibold">Review and approve access to the Global Chatroom.</p>
        </div>
      </Glass>

      {requests.length === 0 ? (
        <div className="text-center py-10 font-bold text-gray-500 bg-[#0B1221] border border-[#1E293B] rounded-3xl">All caught up! No pending requests.</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {requests.map(req => (
            <Glass key={req.id} className="p-5 bg-[#0B1221] border-[#1E293B] rounded-2xl flex flex-col gap-4">
              <div className="flex items-center gap-3">
                <img src={req.userPhoto || '/placeholder.png'} className="w-12 h-12 rounded-full object-cover bg-gray-800" />
                <div className="flex-1 min-w-0">
                  <h3 className="font-black text-white truncate text-base">{req.userName}</h3>
                  <div className="flex items-center gap-1">
                    <span className="text-xs font-mono text-gray-500 truncate">{req.id}</span>
                    <button onClick={() => { navigator.clipboard.writeText(req.id); alert('Copied ID'); }} className="text-gray-500 hover:text-white"><Copy className="w-3 h-3"/></button>
                  </div>
                </div>
              </div>

              <div className="flex gap-2 mt-auto pt-2 border-t border-[#1E293B]">
                <button 
                  onClick={() => handleUpdateStatus(req.id, 'approved')} disabled={!!processingId}
                  className="flex-1 py-2.5 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 flex justify-center items-center gap-2 disabled:opacity-50"
                >
                  {processingId === req.id ? <Loader2 className="w-4 h-4 animate-spin"/> : <CheckCircle className="w-4 h-4"/>} Approve
                </button>
                <button 
                  onClick={() => handleUpdateStatus(req.id, 'rejected')} disabled={!!processingId}
                  className="py-2.5 px-4 bg-red-500/10 text-red-500 font-black rounded-xl hover:bg-red-500/20 flex justify-center items-center disabled:opacity-50"
                >
                  <XCircle className="w-5 h-5"/>
                </button>
              </div>
            </Glass>
          ))}
        </div>
      )}
    </div>
  );
}