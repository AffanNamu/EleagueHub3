'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { QRCodeSVG } from 'qrcode.react';
import { setCookie } from 'cookies-next';
import { signInWithCustomToken } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { createDesktopSession, getDesktopSessionStatus } from '@/lib/desktopPairing';
import { Glass } from '@/components/ui/Glass';
import { Loader2, MonitorSmartphone, RefreshCw, CheckCircle2 } from 'lucide-react';

type PairingStatus = 'generating' | 'waiting' | 'approved' | 'expired' | 'error';

interface DesktopSessionState {
  sessionId: string;
  sessionSecret: string;
  qrPayload: string;
  expiresAtMs: number;
}

const POLL_INTERVAL_MS = 3000;

function formatCountdown(ms: number) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export interface DesktopPairingViewProps {
  onUseEmailInstead?: () => void;
}

export function DesktopPairingView({ onUseEmailInstead }: DesktopPairingViewProps) {
  const router = useRouter();

  const [status, setStatus] = useState<PairingStatus>('generating');
  const [session, setSession] = useState<DesktopSessionState | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [remainingMs, setRemainingMs] = useState(0);

  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const tickTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pairedRef = useRef(false);

  const teardown = useCallback(() => {
    if (pollTimerRef.current) {
      clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
    if (tickTimerRef.current) {
      clearInterval(tickTimerRef.current);
      tickTimerRef.current = null;
    }
  }, []);

  const startPolling = useCallback(
    (s: DesktopSessionState) => {
      teardown();
      pairedRef.current = false;

      pollTimerRef.current = setInterval(async () => {
        if (pairedRef.current) return;

        try {
          const result = await getDesktopSessionStatus(s.sessionId, s.sessionSecret);

          if (result.status === 'approved' || result.status === 'consumed') {
            if (!result.firebaseCustomToken) {
              if (result.customTokenError) {
                console.warn('Custom token mint pending/error:', result.customTokenError);
              }
              return;
            }

            pairedRef.current = true;
            teardown();
            setStatus('approved');

            try {
              const cred = await signInWithCustomToken(auth, result.firebaseCustomToken);
              const idToken = await cred.user.getIdToken();
              setCookie('session', idToken, { maxAge: 60 * 60 * 24 * 5 });
              setTimeout(() => router.push('/leagues'), 900);
            } catch (err) {
              console.error('Custom token sign-in failed', err);
              setStatus('error');
              setErrorMessage('Pairing was approved but sign-in failed. Please refresh and scan again.');
            }
            return;
          }

          if (result.status === 'expired' || result.status === 'rejected') {
            teardown();
            setStatus('expired');
            return;
          }
        } catch (err) {
          console.error('Poll error (will retry):', err);
        }
      }, POLL_INTERVAL_MS);

      tickTimerRef.current = setInterval(() => {
        setRemainingMs((prev) => Math.max(0, prev - 1000));
      }, 1000);
    },
    [router, teardown],
  );

  const startSession = useCallback(async () => {
    teardown();
    setStatus('generating');
    setErrorMessage(null);
    setSession(null);

    try {
      const created = await createDesktopSession();
      const s: DesktopSessionState = {
        sessionId: created.sessionId,
        sessionSecret: created.sessionSecret,
        qrPayload: created.qrPayload,
        expiresAtMs: created.expiresAtMs,
      };

      setSession(s);
      setRemainingMs(Math.max(0, created.expiresAtMs - Date.now()));
      setStatus('waiting');
      startPolling(s);
    } catch (err) {
      console.error('Failed to create desktop session', err);
      setStatus('error');
      setErrorMessage('Could not start pairing. Check your connection and try again.');
    }
  }, [startPolling, teardown]);

  useEffect(() => {
    startSession();
    return teardown;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (status !== 'waiting' || !session) return;
    if (remainingMs <= 0) {
      teardown();
      setStatus('expired');
    }
  }, [remainingMs, status, session, teardown]);

  return (
    <div className="flex flex-col items-center justify-center min-h-[85vh] p-4">
      <div className="text-center mb-10">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-brand-lime/10 border border-brand-lime/30 mb-6">
          <MonitorSmartphone className="w-8 h-8 text-brand-lime" />
        </div>
        <h1 className="text-3xl md:text-4xl font-bold text-white tracking-tight">
          Use eSportlyic on your computer
        </h1>
        <p className="text-gray-400 mt-3 max-w-md mx-auto">
          Open eSportlyic on your phone, go to the QR scanner, and scan this code to link this
          desktop.
        </p>
      </div>

      <Glass intensity="high" className="p-8 md:p-12 flex flex-col items-center w-full max-w-md">
        {status === 'generating' && (
          <div className="w-64 h-64 flex flex-col items-center justify-center gap-4 bg-brand-surface border border-white/5 rounded-2xl">
            <Loader2 className="w-8 h-8 text-brand-lime animate-spin" />
            <p className="text-sm font-medium text-gray-400">Generating secure session...</p>
          </div>
        )}

        {status === 'error' && (
          <div className="w-64 h-64 flex flex-col items-center justify-center gap-4 bg-brand-red/10 border border-brand-red/30 rounded-2xl text-center p-4">
            <p className="text-brand-red font-bold text-sm">Something went wrong</p>
            <p className="text-xs text-gray-400">{errorMessage}</p>
            <button
              onClick={startSession}
              className="mt-2 px-4 py-2 bg-white/10 hover:bg-white/20 rounded-lg text-sm text-white transition-colors flex items-center gap-2"
            >
              <RefreshCw className="w-4 h-4" />
              Try again
            </button>
          </div>
        )}

        {status === 'expired' && (
          <div className="w-64 h-64 flex flex-col items-center justify-center gap-4 bg-brand-surface border border-white/10 rounded-2xl text-center p-4">
            <p className="text-white font-bold text-sm uppercase tracking-wide">Session expired</p>
            <p className="text-xs text-gray-400">
              The connection expired for your security. Generate a new code to scan.
            </p>
            <button
              onClick={startSession}
              className="mt-2 px-4 py-2 bg-brand-lime text-slate-900 font-bold rounded-lg text-sm transition-colors flex items-center gap-2"
            >
              <RefreshCw className="w-4 h-4" />
              Refresh QR
            </button>
          </div>
        )}

        {status === 'approved' && (
          <div className="w-64 h-64 flex flex-col items-center justify-center gap-3 bg-emerald-500/10 border border-emerald-400/30 rounded-2xl">
            <CheckCircle2 className="w-14 h-14 text-emerald-400 animate-bounce" />
            <p className="text-emerald-300 font-bold text-sm">Session approved! Redirecting...</p>
          </div>
        )}

        {status === 'waiting' && session && (
          <div className="relative group">
            <div className="absolute -inset-1 bg-gradient-to-r from-brand-lime to-[#38BDF8] rounded-3xl blur opacity-25 group-hover:opacity-50 transition duration-1000 group-hover:duration-200" />
            <div className="relative bg-white p-4 rounded-2xl">
              <QRCodeSVG
                value={session.qrPayload}
                size={240}
                bgColor="#ffffff"
                fgColor="#081120"
                level="H"
                includeMargin={false}
              />
            </div>
          </div>
        )}

        <div className="mt-8 text-center space-y-4 w-full">
          {status === 'waiting' && (
            <>
              <div className="flex items-center justify-center gap-2 text-brand-lime">
                <span className="relative flex h-3 w-3">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-brand-lime opacity-75" />
                  <span className="relative inline-flex rounded-full h-3 w-3 bg-brand-lime" />
                </span>
                <span className="font-semibold text-sm">Waiting for mobile scan...</span>
              </div>
              <p className="text-xs text-gray-500">Expires in {formatCountdown(remainingMs)}</p>
            </>
          )}

          {onUseEmailInstead && (
            <div className="pt-6 border-t border-white/10 w-full mt-4">
              <p className="text-xs text-gray-500">Don&apos;t have your phone handy?</p>
              <button
                onClick={onUseEmailInstead}
                className="mt-2 text-sm text-brand-lime hover:underline font-medium"
              >
                Sign in with email &amp; password instead
              </button>
            </div>
          )}
        </div>
      </Glass>
    </div>
  );
}
