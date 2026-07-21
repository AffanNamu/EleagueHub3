'use client';

import React, { useState } from 'react';
import { SuperAdminGuard } from '@/components/guards/SuperAdminGuard';
import { Glass } from '@/components/ui/Glass';
import { ShieldAlert, Send, Activity, Info, Loader2 } from 'lucide-react';
import { collection, doc, setDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export default function SuperAdminDashboard() {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [type, setType] = useState<'update' | 'alert' | 'maintenance'>('update');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [statusMsg, setStatusMsg] = useState<{ text: string, type: 'success' | 'error' } | null>(null);

  const handlePublish = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !message.trim()) return;

    setIsSubmitting(true);
    setStatusMsg(null);

    try {
      const ref = doc(collection(db, 'platform_announcements'));
      await setDoc(ref, {
        title: title.trim(),
        message: message.trim(),
        type,
        createdAtMs: Date.now(),
        authorName: auth.currentUser?.displayName || 'System Admin',
        authorId: auth.currentUser?.uid
      });

      setTitle('');
      setMessage('');
      setStatusMsg({ text: 'Transmission broadcasted globally.', type: 'success' });
    } catch (error: any) {
      console.error(error);
      setStatusMsg({ text: `Failed to broadcast: ${error.message}`, type: 'error' });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <SuperAdminGuard>
      <div className="max-w-4xl mx-auto space-y-8 pb-20">
        
        {/* SECURE HEADER */}
        <div className="flex items-center gap-4 border-b border-brand-red/20 pb-6">
          <div className="w-14 h-14 rounded-xl bg-brand-red/10 border border-brand-red/30 flex items-center justify-center shrink-0 shadow-[0_0_20px_rgba(239,68,68,0.2)]">
            <ShieldAlert className="w-7 h-7 text-brand-red" />
          </div>
          <div>
            <h1 className="text-3xl font-black text-white tracking-tight">Super Admin Portal</h1>
            <p className="text-brand-red/80 font-bold text-sm tracking-wider uppercase mt-1">Level 5 Access Granted</p>
          </div>
        </div>

        {/* COMMS TRANSMITTER */}
        <Glass className="p-6 border border-brand-red/20 relative overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-brand-red/5 blur-[100px] pointer-events-none"></div>
          
          <h2 className="text-xl font-black text-white flex items-center gap-2 mb-6">
            <Activity className="w-5 h-5 text-brand-red" /> Global Transmission
          </h2>

          <form onSubmit={handlePublish} className="space-y-5 relative z-10">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="md:col-span-2 space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase tracking-wider">Transmission Title</label>
                <input 
                  type="text" 
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. New Swiss Format Deployed"
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-3 text-white focus:outline-none focus:border-brand-red/50 transition-colors"
                  required
                />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-gray-400 uppercase tracking-wider">Classification</label>
                <select 
                  value={type}
                  onChange={(e) => setType(e.target.value as any)}
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-3 text-white focus:outline-none focus:border-brand-red/50 transition-colors appearance-none"
                >
                  <option value="update">Platform Update (Purple)</option>
                  <option value="alert">Event Alert (Lime)</option>
                  <option value="maintenance">Maintenance (Red)</option>
                </select>
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-bold text-gray-400 uppercase tracking-wider">Transmission Payload</label>
              <textarea 
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder="Enter the broadcast message..."
                rows={4}
                className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl px-4 py-3 text-white focus:outline-none focus:border-brand-red/50 transition-colors resize-none"
                required
              />
            </div>

            {statusMsg && (
              <div className={`p-4 rounded-xl text-sm font-bold flex items-center gap-2 ${statusMsg.type === 'success' ? 'bg-brand-lime/10 text-brand-lime border border-brand-lime/20' : 'bg-brand-red/10 text-brand-red border border-brand-red/20'}`}>
                <Info className="w-4 h-4" /> {statusMsg.text}
              </div>
            )}

            <div className="pt-2">
              <button 
                type="submit" 
                disabled={isSubmitting}
                className="w-full md:w-auto px-8 py-3.5 bg-brand-red text-white font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {isSubmitting ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
                {isSubmitting ? 'Broadcasting...' : 'Broadcast Transmission'}
              </button>
            </div>
          </form>
        </Glass>
      </div>
    </SuperAdminGuard>
  );
}
