'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { createMasterLeagueWeb } from '@/lib/masterLeagues/masterLeaguesRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Network as Hub, CheckCircle2, ShieldAlert } from 'lucide-react';

export default function CreateMasterLeagueScreen() {
  const router = useRouter();
  
  const [name, setName] = useState('');
  const [compName, setCompName] = useState('');
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState('');

  const handleCreate = async () => {
    if (!name.trim() || !compName.trim()) return setError('Please fill out both fields.');
    const uid = auth.currentUser?.uid;
    if (!uid) return router.push('/login');

    setProcessing(true);
    setError('');

    try {
      // Create the workspace using the strict payload required by Rules
      const newId = await createMasterLeagueWeb({ name, compName, authUid: uid });
      router.push(`/master-leagues/${newId}`);
    } catch (err: any) {
      setError(err.message || 'Creation failed. Check permissions.');
    } finally {
      setProcessing(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white"/>
        </button>
      </div>

      <Glass className="p-6 md:p-10 border border-[#1E293B] bg-[#0B1221] rounded-3xl shadow-2xl">
        <div className="flex items-center gap-4 mb-6">
          <div className="w-12 h-12 rounded-full bg-[#BEF264]/10 border border-[#BEF264]/30 flex items-center justify-center shrink-0">
            <Hub className="w-6 h-6 text-[#BEF264]"/>
          </div>
          <div>
            <h1 className="text-xl md:text-2xl font-black text-white">Create New Workspace</h1>
            <p className="text-sm font-semibold text-gray-400">Establish your organizer brand.</p>
          </div>
        </div>

        {error && (
          <div className="p-4 mb-6 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm font-bold flex items-center gap-2">
            <ShieldAlert className="w-5 h-5"/> {error}
          </div>
        )}

        <div className="space-y-5">
          <div>
            <label className="block text-xs font-black uppercase tracking-widest text-gray-500 mb-2">Master League Name</label>
            <input 
              value={name} onChange={e => setName(e.target.value)} disabled={processing}
              placeholder="e.g. ESL Global, Pro League Series"
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-sm font-bold text-white outline-none focus:border-[#BEF264] transition-colors" 
            />
          </div>
          <div>
            <label className="block text-xs font-black uppercase tracking-widest text-gray-500 mb-2">Initial Competition Name</label>
            <input 
              value={compName} onChange={e => setCompName(e.target.value)} disabled={processing}
              placeholder="e.g. Summer Cup 2026"
              className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-sm font-bold text-white outline-none focus:border-[#BEF264] transition-colors" 
            />
          </div>

          <div className="pt-6 mt-6 border-t border-[#1E293B]">
            <button 
              onClick={handleCreate} disabled={processing}
              className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-[#BEF264]/20 transition-all active:scale-95"
            >
              {processing ? <Loader2 className="w-5 h-5 animate-spin"/> : <CheckCircle2 className="w-5 h-5"/>}
              Create Workspace
            </button>
            <p className="text-center text-xs font-semibold text-gray-500 mt-4">Free Basic Plan workspace will be created by default.</p>
          </div>
        </div>
      </Glass>
    </div>
  );
}
