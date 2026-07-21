'use client';

import { useState } from 'react';
import { X, Key, QrCode, Loader2, Users, Eye } from 'lucide-react';

export interface JoinLeagueModalProps {
  onClose: () => void;
  onJoin: (code: string, mode: 'participant' | 'viewer') => Promise<void>;
}

type Tab = 'code' | 'qr';

export function JoinLeagueModal({ onClose, onJoin }: JoinLeagueModalProps) {
  const [tab, setTab] = useState<Tab>('code');
  const [code, setCode] = useState('');
  const [mode, setMode] = useState<'participant' | 'viewer'>('participant');
  const [joining, setJoining] = useState(false);
  const [error, setError] = useState('');

  const handleJoin = async () => {
    if (!code.trim()) {
      setError('Please enter a join code.');
      return;
    }
    setJoining(true);
    setError('');
    try {
      await onJoin(code.trim().toUpperCase(), mode);
    } catch (e: any) {
      setError(e?.message ?? 'Something went wrong. Please try again.');
      setJoining(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="w-full max-w-md bg-white dark:bg-[#0F172A] rounded-3xl shadow-2xl border border-transparent dark:border-white/10 overflow-hidden transition-colors duration-300">
        <div className="flex items-center justify-between p-5 border-b border-slate-100 dark:border-white/10">
          <h2 className="text-lg font-black text-slate-900 dark:text-white">Join a league</h2>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 transition-colors">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex border-b border-slate-100 dark:border-white/10">
          <TabButton active={tab === 'code'} onClick={() => setTab('code')} icon={Key} label="Enter code" />
          <TabButton active={tab === 'qr'} onClick={() => setTab('qr')} icon={QrCode} label="Scan QR" />
        </div>

        <div className="p-6">
          {tab === 'code' ? (
            <>
              <label className="block text-xs font-bold text-slate-500 dark:text-slate-400 mb-2 uppercase tracking-wide">
                Join code
              </label>
              <input
                type="text"
                value={code}
                onChange={(e) => {
                  setCode(e.target.value);
                  setError('');
                }}
                onKeyDown={(e) => e.key === 'Enter' && handleJoin()}
                placeholder="e.g. 7K2P9Q"
                autoFocus
                className="w-full px-4 py-3.5 bg-slate-50 dark:bg-[#081120] border border-slate-200 dark:border-white/10 focus:border-brand-lime dark:focus:border-brand-lime rounded-2xl text-slate-900 dark:text-white font-black tracking-widest uppercase placeholder:font-medium placeholder:tracking-normal focus:outline-none transition-all"
              />

              <p className="text-xs font-bold text-slate-500 dark:text-slate-400 mt-5 mb-2 uppercase tracking-wide">Join as</p>
              <div className="grid grid-cols-2 gap-2">
                <ModeCard
                  active={mode === 'participant'}
                  onClick={() => setMode('participant')}
                  icon={Users}
                  label="Participant"
                  description="Compete and appear in standings"
                />
                <ModeCard
                  active={mode === 'viewer'}
                  onClick={() => setMode('viewer')}
                  icon={Eye}
                  label="Viewer only"
                  description="Follow along without competing"
                />
              </div>

              {error && (
                <div className="mt-4 bg-red-50 dark:bg-red-500/10 text-red-500 dark:text-red-400 border border-red-100 dark:border-red-500/20 text-xs font-bold py-2.5 px-4 rounded-xl text-center">
                  {error}
                </div>
              )}

              <button
                onClick={handleJoin}
                disabled={joining}
                className="w-full mt-5 py-3.5 bg-brand-lime text-slate-900 font-black rounded-2xl hover:brightness-95 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {joining ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Join league'}
              </button>
            </>
          ) : (
            <div className="text-center py-6">
              <div className="w-16 h-16 mx-auto rounded-2xl bg-brand-lime/10 border border-brand-lime/30 flex items-center justify-center mb-4">
                <QrCode className="w-8 h-8 text-brand-lime" />
              </div>
              <p className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1">Scan with the eSportlyic app</p>
              <p className="text-xs text-slate-400 dark:text-slate-500 leading-relaxed max-w-xs mx-auto">
                Camera-based QR scanning isn't available in the browser yet — open the mobile app and
                use its scanner, or switch to the "Enter code" tab to join manually.
              </p>
              <button
                onClick={() => setTab('code')}
                className="mt-5 text-sm font-bold text-brand-lime hover:underline"
              >
                Enter code instead
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function TabButton({
  active,
  onClick,
  icon: Icon,
  label,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ComponentType<{ className?: string }>;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 flex items-center justify-center gap-2 py-3 text-sm font-bold transition-colors ${
        active 
          ? 'text-brand-lime border-b-2 border-brand-lime' 
          : 'text-slate-400 hover:text-slate-600 dark:hover:text-slate-300'
      }`}
    >
      <Icon className="w-4 h-4" />
      {label}
    </button>
  );
}

function ModeCard({
  active,
  onClick,
  icon: Icon,
  label,
  description,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  description: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`text-left p-3 rounded-xl border transition-all ${
        active 
          ? 'bg-brand-lime/10 border-brand-lime' 
          : 'bg-slate-50 dark:bg-white/5 border-slate-200 dark:border-white/10 hover:bg-slate-100 dark:hover:bg-white/10'
      }`}
    >
      <Icon className={`w-4 h-4 mb-1.5 ${active ? 'text-brand-lime' : 'text-slate-400 dark:text-slate-500'}`} />
      <p className={`text-xs font-black ${active ? 'text-slate-900 dark:text-white' : 'text-slate-600 dark:text-slate-400'}`}>{label}</p>
      <p className="text-[10px] text-slate-400 dark:text-slate-500 font-medium leading-tight mt-0.5">{description}</p>
    </button>
  );
}
