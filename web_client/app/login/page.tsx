'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { v4 as uuidv4 } from 'uuid';
import QRCode from 'react-qr-code';
import { supabase } from '@/lib/supabaseClient';
import { auth } from '@/lib/firebase';
import { 
  signInWithEmailAndPassword, 
  signInWithPopup, 
  GoogleAuthProvider 
} from 'firebase/auth';
import { 
  Loader2, 
  RefreshCw, 
  QrCode, 
  Mail, 
  Lock, 
  Gamepad2,
  CheckCircle2,
  MonitorSmartphone
} from 'lucide-react';

export default function LoginScreen() {
  const router = useRouter();
  
  // View Toggle State: 'signin' or 'pairing'
  const [viewMode, setViewMode] = useState<'signin' | 'pairing'>('signin');
  
  // Auth Form States
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [authLoading, setAuthLoading] = useState(false);
  const [authError, setAuthError] = useState('');

  // Web Pairing States
  const [sessionId, setSessionId] = useState<string>('');
  const [pairingStatus, setPairingStatus] = useState<'generating' | 'waiting' | 'approved' | 'failed'>('generating');

  // --- STANDARD FIREBASE AUTH HANDLERS ---
  const handleEmailSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) {
      setAuthError('Please fill in all fields.');
      return;
    }
    setAuthLoading(true);
    setAuthError('');
    try {
      await signInWithEmailAndPassword(auth, email, password);
      router.push('/leagues');
    } catch (err: any) {
      console.error(err);
      setAuthError(err.message || 'Invalid email or password.');
    } finally {
      setAuthLoading(false);
    }
  };

  const handleGoogleSignIn = async () => {
    setAuthLoading(true);
    setAuthError('');
    const provider = new GoogleAuthProvider();
    try {
      await signInWithPopup(auth, provider);
      router.push('/leagues');
    } catch (err: any) {
      console.error(err);
      setAuthError(err.message || 'Google sign-in failed.');
    } finally {
      setAuthLoading(false);
    }
  };

  // --- SUPABASE DESKTOP PAIRING HANDLERS ---
  const generateNewSession = async () => {
    setPairingStatus('generating');
    const newId = uuidv4();
    setSessionId(newId);

    try {
      const { error } = await supabase.from('desktop_sessions').insert([{
        session_id: newId,
        status: 'pending',
        created_at_ms: Date.now(),
      }]);
      
      if (error) throw error;
      setPairingStatus('waiting');
    } catch (err) {
      console.error("Failed to create session", err);
      setPairingStatus('failed');
    }
  };

  useEffect(() => {
    if (viewMode === 'pairing') {
      generateNewSession();
    }
  }, [viewMode]);

  // Listen for Mobile App scanning the QR code
  useEffect(() => {
    if (!sessionId || pairingStatus !== 'waiting' || viewMode !== 'pairing') return;

    const channel = supabase
      .channel(`session_${sessionId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'desktop_sessions', filter: `session_id=eq.${sessionId}` },
        async (payload) => {
          const newStatus = payload.new.status;
          
          if (newStatus === 'approved') {
            setPairingStatus('approved');
            // Simulate success and route to dashboard
            setTimeout(() => {
              router.push('/leagues');
            }, 1500);
          } else if (newStatus === 'rejected' || newStatus === 'expired') {
            setPairingStatus('failed');
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [sessionId, pairingStatus, viewMode, router]);

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-6 relative overflow-hidden font-sans">
      
      {/* Premium Subtle Ambient Background Orbs */}
      <div className="absolute top-0 left-0 w-full h-full overflow-hidden pointer-events-none z-0">
        <div className="absolute -top-40 -left-40 w-[600px] h-[600px] bg-brand-lime opacity-10 rounded-full blur-[120px]"></div>
        <div className="absolute top-1/2 right-0 w-[500px] h-[500px] bg-sky-400 opacity-10 rounded-full blur-[120px] transform translate-x-1/3"></div>
      </div>

      <div className="w-full max-w-md z-10 space-y-6">
        
        {/* VIEW MODE TOGGLE BUTTON */}
        <div className="flex justify-end">
          <button
            onClick={() => setViewMode(viewMode === 'signin' ? 'pairing' : 'signin')}
            className="flex items-center gap-2 px-4 py-2 bg-white/80 hover:bg-white border border-slate-200/80 text-slate-800 text-xs font-bold rounded-full shadow-sm transition-all transform active:scale-95"
          >
            {viewMode === 'signin' ? (
              <>
                <QrCode className="w-4 h-4 text-brand-lime" />
                <span>Switch to Web Pairing</span>
              </>
            ) : (
              <>
                <MonitorSmartphone className="w-4 h-4 text-brand-lime" />
                <span>Switch to Standard Sign In</span>
              </>
            )}
          </button>
        </div>

        {/* ----------------- VIEW 1: STANDARD AUTH SIGN IN ----------------- */}
        {viewMode === 'signin' && (
          <div className="bg-white rounded-3xl p-8 md:p-10 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-slate-100 flex flex-col items-center">
            
            {/* Smooth Brand Squircle (Game Controller Icon) */}
            <div className="w-16 h-16 bg-brand-lime rounded-[24px] flex items-center justify-center shadow-[0_10px_25px_rgba(163,230,53,0.35)] mb-6">
              <Gamepad2 className="w-8 h-8 text-slate-900" />
            </div>

            <h1 className="text-3xl font-black text-slate-900 tracking-tight mb-1">eSportlyic</h1>
            <p className="text-slate-400 text-sm font-semibold mb-8">Sign in to continue.</p>

            {/* Error Message Display */}
            {authError && (
              <div className="w-full bg-red-50 text-red-500 border border-red-100 text-xs font-bold py-3 px-4 rounded-xl mb-4 text-center">
                {authError}
              </div>
            )}

            {/* Google Authentication Button */}
            <button
              onClick={handleGoogleSignIn}
              disabled={authLoading}
              className="w-full py-3.5 bg-slate-50 hover:bg-slate-100 border border-slate-200 text-slate-700 font-bold rounded-2xl transition-all flex items-center justify-center gap-3 text-sm disabled:opacity-50"
            >
              {/* Premium Google Brand Vector Logo */}
              <svg className="w-5 h-5 shrink-0" viewBox="0 0 24 24">
                <path
                  fill="#4285F4"
                  d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v3.92h6.69c-.29 1.5-.14 2.08-1.42 2.93v2.42h2.29c2.37-2.18 3.73-5.39 3.73-9.2z"
                />
                <path
                  fill="#34A853"
                  d="M12 24c3.24 0 5.97-1.08 7.96-2.91l-3.87-3c-1.08.72-2.45 1.16-4.09 1.16-3.15 0-5.81-2.13-6.76-4.99H2.89v3.08C4.88 20.24 8.21 24 12 24z"
                />
                <path
                  fill="#FBBC05"
                  d="M5.24 14.26c-.25-.72-.39-1.49-.39-2.26s.14-1.54.39-2.26V6.66H2.89C2.06 8.3 1.58 10.1 1.58 12s.48 3.7 1.31 5.34l2.35-3.08z"
                />
                <path
                  fill="#EA4335"
                  d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.96 1.19 15.24 0 12 0 8.21 0 4.88 3.76 2.89 7.74l3.59 3.08c.95-2.86 3.61-4.99 6.76-4.99z"
                />
              </svg>
              Continue with Google
            </button>

            {/* OR Divider */}
            <div className="flex items-center w-full gap-4 text-slate-300 my-6">
              <div className="h-px bg-slate-200 flex-1"></div>
              <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">OR</span>
              <div className="h-px bg-slate-200 flex-1"></div>
            </div>

            {/* Credentials Login Form */}
            <form onSubmit={handleEmailSignIn} className="w-full space-y-4">
              <div className="relative">
                <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                <input
                  type="email"
                  placeholder="Email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full pl-12 pr-4 py-3.5 bg-slate-50 border border-slate-200/80 focus:border-brand-lime rounded-2xl text-slate-900 placeholder:text-slate-400 font-medium text-sm focus:outline-none transition-all focus:bg-white"
                />
              </div>

              <div className="relative">
                <Lock className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                <input
                  type="password"
                  placeholder="Password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full pl-12 pr-4 py-3.5 bg-slate-50 border border-slate-200/80 focus:border-brand-lime rounded-2xl text-slate-900 placeholder:text-slate-400 font-medium text-sm focus:outline-none transition-all focus:bg-white"
                />
              </div>

              <div className="text-right">
                <a href="#" className="text-xs font-bold text-brand-lime hover:underline">Forgot password?</a>
              </div>

              <button
                type="submit"
                disabled={authLoading}
                className="w-full py-3.5 bg-brand-lime text-slate-900 font-black rounded-2xl hover:brightness-95 transition-all shadow-lg shadow-brand-lime/20 flex items-center justify-center gap-2 text-sm disabled:opacity-50"
              >
                {authLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign in'}
              </button>
            </form>

            {/* Create Account Link */}
            <div className="mt-8 text-xs font-semibold text-slate-500">
              No account? <a href="#" className="text-brand-lime font-bold hover:underline">Create one</a>
            </div>

          </div>
        )}

        {/* ----------------- VIEW 2: HIGH-END IOS WEB PAIRING ----------------- */}
        {viewMode === 'pairing' && (
          <div className="space-y-4">
            
            {/* GORGEOUS QR CODE PANEL */}
            <div className="bg-white rounded-[32px] p-8 md:p-10 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-slate-100 flex flex-col items-center">
              
              {/* White outer QR boundary shadow box */}
              <div className="bg-white p-5 rounded-3xl border border-slate-100 shadow-[0_15px_40px_rgba(0,0,0,0.03)] mb-6 relative">
                {pairingStatus === 'generating' ? (
                  <div className="w-48 h-48 flex flex-col items-center justify-center gap-2">
                    <Loader2 className="w-10 h-10 animate-spin text-brand-lime" />
                    <p className="text-[10px] font-bold text-slate-400">GENERATE...</p>
                  </div>
                ) : pairingStatus === 'approved' ? (
                  <div className="w-48 h-48 flex flex-col items-center justify-center bg-emerald-50 rounded-2xl">
                    <CheckCircle2 className="w-14 h-14 text-emerald-500 mb-2 animate-bounce" />
                    <p className="text-emerald-600 font-bold text-sm">Session Approved!</p>
                  </div>
                ) : (
                  <div className="relative p-1">
                    <QRCode value={sessionId} size={180} fgColor="#0F172A" />
                    
                    {/* Session Expired Overlay (No overlap, perfectly centered) */}
                    {pairingStatus === 'failed' && (
                      <div className="absolute inset-0 bg-white/95 backdrop-blur-[2px] flex flex-col items-center justify-center rounded-xl p-4 text-center">
                        <p className="text-red-500 font-black text-sm mb-1 uppercase tracking-wider">Session Expired</p>
                        <p className="text-slate-400 text-[10px] font-medium leading-relaxed">The connection expired. Regenerate to scan.</p>
                      </div>
                    )}
                  </div>
                )}
              </div>

              {/* Status Header */}
              <h2 className="text-md font-extrabold text-slate-800 tracking-tight mb-1">Scan to link this desktop</h2>
              <p className="text-slate-400 text-xs font-semibold max-w-[280px] leading-relaxed mb-6">
                Open the eSportlyic mobile app and scan this QR code.
              </p>

              {/* Refresh Pill Button */}
              <button 
                onClick={generateNewSession}
                disabled={pairingStatus === 'generating' || pairingStatus === 'approved'}
                className="flex items-center justify-center gap-2 px-5 py-2.5 bg-brand-lime hover:brightness-95 text-slate-900 text-xs font-black rounded-full shadow-sm shadow-brand-lime/25 transition-all disabled:opacity-40"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${pairingStatus === 'generating' ? 'animate-spin' : ''}`} />
                Refresh QR
              </button>

            </div>

            {/* INFORMATION INSTRUCTIONS CONTAINER */}
            <div className="bg-white rounded-2xl p-6 shadow-[0_4px_20px_rgb(0,0,0,0.02)] border border-slate-100 flex items-start gap-4">
              <div className="w-10 h-10 bg-brand-lime rounded-xl flex items-center justify-center shrink-0 shadow-sm shadow-brand-lime/10">
                <Gamepad2 className="w-5 h-5 text-slate-900" />
              </div>
              
              <div className="text-left space-y-1">
                <h3 className="text-sm font-black text-slate-800">Use eSportlyic on your computer</h3>
                <ol className="text-xs text-slate-400 font-semibold list-decimal list-inside space-y-1 leading-normal">
                  <li>Open eSportlyic on your phone</li>
                  <li>Go to the QR scanner</li>
                  <li>Scan this code to link your desktop</li>
                </ol>
              </div>
            </div>

          </div>
        )}

      </div>
    </div>
  );
}
