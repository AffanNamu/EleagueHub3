'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signInWithPopup,
  signOut,
  GoogleAuthProvider,
  User
} from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { Loader2, Mail, Lock, Gamepad2, Eye, EyeOff, QrCode, ArrowRight, LogOut } from 'lucide-react';

export interface MobileSignInViewProps {
  onUsePairingInstead?: () => void;
}

export function MobileSignInView({ onUsePairingInstead }: MobileSignInViewProps) {
  const router = useRouter();

  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [obscurePassword, setObscurePassword] = useState(true);
  const [obscureConfirm, setObscureConfirm] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  
  const [loggedInUser, setLoggedInUser] = useState<User | null>(null);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (user) {
        try {
          const idToken = await user.getIdToken();
          const maxAge = 60 * 60 * 24 * 5;
          document.cookie = `session=${idToken}; path=/; max-age=${maxAge}; Secure; SameSite=Lax`;
          setLoggedInUser(user);
        } catch (err) {
          console.error("Failed to set session cookie", err);
        }
      } else {
        setLoggedInUser(null);
      }
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  const handleGoogleSignIn = async () => {
    setLoading(true);
    setError('');
    try {
      const provider = new GoogleAuthProvider();
      await signInWithPopup(auth, provider);
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'Google sign-in failed.');
      setLoading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) {
      setError('Please fill in all fields.');
      return;
    }
    if (isSignUp && password !== confirm) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);
    setError('');
    try {
      if (isSignUp) {
        await createUserWithEmailAndPassword(auth, email, password);
      } else {
        await signInWithEmailAndPassword(auth, email, password);
      }
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'Invalid email or password.');
      setLoading(false);
    }
  };

  // THE BULLETPROOF LOGOUT
  const handleSignOut = async () => {
    setLoading(true);
    try {
      await signOut(auth);
      // Nuke the cookie using all possible flags to ensure it dies
      document.cookie = 'session=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/; Secure; SameSite=Lax';
      document.cookie = 'session=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
      
      // Force a hard browser reload to the homepage to completely clear Next.js memory!
      window.location.href = '/';
    } catch (err) {
      console.error('Error signing out:', err);
      setLoading(false);
    }
  };

  if (loading && !loggedInUser) {
    return (
      <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-6">
        <Loader2 className="w-8 h-8 text-brand-lime animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-6 relative overflow-hidden font-sans">
      <div className="absolute top-0 left-0 w-full h-full overflow-hidden pointer-events-none z-0">
        <div className="absolute -top-40 -left-40 w-[600px] h-[600px] bg-brand-lime opacity-10 rounded-full blur-[120px]" />
        <div className="absolute top-1/2 right-0 w-[500px] h-[500px] bg-sky-400 opacity-10 rounded-full blur-[120px] transform translate-x-1/3" />
      </div>

      <div className="w-full max-w-md z-10">
        <div className="bg-white rounded-3xl p-8 md:p-10 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-slate-100 flex flex-col items-center">
          <div className="w-16 h-16 bg-brand-lime rounded-[24px] flex items-center justify-center shadow-[0_10px_25px_rgba(163,230,53,0.35)] mb-6">
            <Gamepad2 className="w-8 h-8 text-slate-900" />
          </div>

          <h1 className="text-3xl font-black text-slate-900 tracking-tight mb-1">eSportlyic</h1>
          
          {loggedInUser ? (
            <div className="w-full mt-4 flex flex-col items-center text-center">
              <p className="text-slate-500 font-semibold mb-6">You are already signed in.</p>
              
              <div className="w-full p-4 bg-slate-50 border border-slate-200 rounded-2xl mb-8 flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-brand-lime/20 flex items-center justify-center shrink-0">
                  <span className="font-bold text-slate-700">{loggedInUser.email?.charAt(0).toUpperCase() || 'U'}</span>
                </div>
                <div className="text-left overflow-hidden">
                  <p className="text-sm font-bold text-slate-900 truncate">{loggedInUser.displayName || 'Gamer'}</p>
                  <p className="text-xs text-slate-500 truncate">{loggedInUser.email}</p>
                </div>
              </div>

              <button
                onClick={() => {
                  setLoading(true);
                  router.push('/onboarding');
                }}
                disabled={loading}
                className="w-full py-4 bg-brand-lime text-slate-900 font-black rounded-2xl hover:brightness-95 transition-all shadow-lg flex items-center justify-center gap-2 mb-4"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : (
                  <>Continue to Dashboard <ArrowRight className="w-4 h-4" /></>
                )}
              </button>

              <button
                onClick={handleSignOut}
                disabled={loading}
                className="w-full py-4 bg-white border border-slate-200 text-slate-600 font-bold rounded-2xl hover:bg-slate-50 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <><LogOut className="w-4 h-4" /> Sign out</>}
              </button>
            </div>
          ) : (
            <>
              <p className="text-slate-400 text-sm font-semibold mb-8">
                {isSignUp ? 'Create your account' : 'Sign in to continue.'}
              </p>

              {error && (
                <div className="w-full bg-red-50 text-red-500 border border-red-100 text-xs font-bold py-3 px-4 rounded-xl mb-4 text-center">
                  {error}
                </div>
              )}

              <button
                onClick={handleGoogleSignIn}
                disabled={loading}
                className="w-full py-3.5 bg-slate-50 hover:bg-slate-100 border border-slate-200 text-slate-700 font-bold rounded-2xl transition-all flex items-center justify-center gap-3 text-sm disabled:opacity-50"
              >
                {loading ? <Loader2 className="w-5 h-5 animate-spin text-slate-400" /> : (
                  <>
                    <svg width="20" height="20" style={{ minWidth: '20px', minHeight: '20px', maxWidth: '20px' }} viewBox="0 0 24 24">
                      <path fill="#4285F4" d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v3.92h6.69c-.29 1.5-.14 2.08-1.42 2.93v2.42h2.29c2.37-2.18 3.73-5.39 3.73-9.2z" />
                      <path fill="#34A853" d="M12 24c3.24 0 5.97-1.08 7.96-2.91l-3.87-3c-1.08.72-2.45 1.16-4.09 1.16-3.15 0-5.81-2.13-6.76-4.99H2.89v3.08C4.88 20.24 8.21 24 12 24z" />
                      <path fill="#FBBC05" d="M5.24 14.26c-.25-.72-.39-1.49-.39-2.26s.14-1.54.39-2.26V6.66H2.89C2.06 8.3 1.58 10.1 1.58 12s.48 3.7 1.31 5.34l2.35-3.08z" />
                      <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.96 1.19 15.24 0 12 0 8.21 0 4.88 3.76 2.89 7.74l3.59 3.08c.95-2.86 3.61-4.99 6.76-4.99z" />
                    </svg>
                    Continue with Google
                  </>
                )}
              </button>

              <div className="flex items-center w-full gap-4 text-slate-300 my-6">
                <div className="h-px bg-slate-200 flex-1" />
                <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">OR</span>
                <div className="h-px bg-slate-200 flex-1" />
              </div>

              <form onSubmit={handleSubmit} className="w-full space-y-4">
                <div className="relative">
                  <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                  <input
                    type="email"
                    placeholder="Email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    disabled={loading}
                    className="w-full pl-12 pr-4 py-3.5 bg-slate-50 border border-slate-200/80 focus:border-brand-lime rounded-2xl text-slate-900 placeholder:text-slate-400 font-medium text-sm focus:outline-none transition-all focus:bg-white"
                  />
                </div>

                <div className="relative">
                  <Lock className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                  <input
                    type={obscurePassword ? 'password' : 'text'}
                    placeholder="Password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    disabled={loading}
                    className="w-full pl-12 pr-11 py-3.5 bg-slate-50 border border-slate-200/80 focus:border-brand-lime rounded-2xl text-slate-900 placeholder:text-slate-400 font-medium text-sm focus:outline-none transition-all focus:bg-white"
                  />
                  <button type="button" onClick={() => setObscurePassword((v) => !v)} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600">
                    {obscurePassword ? <Eye className="w-5 h-5" /> : <EyeOff className="w-5 h-5" />}
                  </button>
                </div>

                {isSignUp && (
                  <div className="relative">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                    <input
                      type={obscureConfirm ? 'password' : 'text'}
                      placeholder="Confirm password"
                      value={confirm}
                      onChange={(e) => setConfirm(e.target.value)}
                      disabled={loading}
                      className="w-full pl-12 pr-11 py-3.5 bg-slate-50 border border-slate-200/80 focus:border-brand-lime rounded-2xl text-slate-900 placeholder:text-slate-400 font-medium text-sm focus:outline-none transition-all focus:bg-white"
                    />
                    <button type="button" onClick={() => setObscureConfirm((v) => !v)} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600">
                      {obscureConfirm ? <Eye className="w-5 h-5" /> : <EyeOff className="w-5 h-5" />}
                    </button>
                  </div>
                )}

                {!isSignUp && (
                  <div className="text-right">
                    <a href="/forgot-password" className="text-xs font-bold text-brand-lime hover:underline">
                      Forgot password?
                    </a>
                  </div>
                )}

                <button type="submit" disabled={loading} className="w-full py-3.5 bg-brand-lime text-slate-900 font-black rounded-2xl hover:brightness-95 transition-all shadow-lg shadow-brand-lime/20 flex items-center justify-center gap-2 text-sm disabled:opacity-50">
                  {loading ? <Loader2 className="w-5 h-5 animate-spin text-slate-900" /> : (isSignUp ? 'Create account' : 'Sign in')}
                </button>
              </form>

              <div className="mt-8 text-xs font-semibold text-slate-500">
                {isSignUp ? 'Already have an account?' : 'No account?'}{' '}
                <button
                  onClick={() => {
                    setIsSignUp((v) => !v);
                    setError('');
                  }}
                  className="text-brand-lime font-bold hover:underline"
                >
                  {isSignUp ? 'Sign in' : 'Create one'}
                </button>
              </div>

              {onUsePairingInstead && (
                <button onClick={onUsePairingInstead} className="mt-6 flex items-center gap-2 px-4 py-2 bg-slate-50 hover:bg-slate-100 border border-slate-200 text-slate-600 text-xs font-bold rounded-full transition-all">
                  <QrCode className="w-4 h-4 text-brand-lime" />
                  Sign in with QR pairing instead
                </button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
