'use client';

import { useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  signInWithEmailAndPassword,
  signInWithPopup,
  type UserCredential,
} from 'firebase/auth';
import { auth, googleAuthProvider } from '@/lib/firebase';

function friendlyAuthError(code: string): string {
  switch (code) {
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found':
      return 'That email and password combination is not recognized.';
    case 'auth/too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'auth/popup-closed-by-user':
      return 'Sign-in was cancelled.';
    default:
      return 'Sign-in failed. Please try again.';
  }
}

export default function LoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const nextPath = searchParams.get('next') ?? '/dashboard';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function establishSession(credential: UserCredential) {
    const idToken = await credential.user.getIdToken();

    const response = await fetch('/api/admin/auth/session', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.error ?? 'You do not have access to this workspace.');
    }

    router.replace(nextPath);
    router.refresh();
  }

  async function handleEmailSignIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;

    setSubmitting(true);
    setError(null);

    try {
      const credential = await signInWithEmailAndPassword(auth, email.trim(), password);
      await establishSession(credential);
    } catch (err) {
      const code = err && typeof err === 'object' && 'code' in err ? String(err.code) : '';
      setError(code ? friendlyAuthError(code) : 'Sign-in failed. Please try again.');
      setSubmitting(false);
    }
  }

  async function handleGoogleSignIn() {
    if (submitting) return;

    setSubmitting(true);
    setError(null);

    try {
      const credential = await signInWithPopup(auth, googleAuthProvider);
      await establishSession(credential);
    } catch (err) {
      const code = err && typeof err === 'object' && 'code' in err ? String(err.code) : '';
      setError(code ? friendlyAuthError(code) : 'Sign-in failed. Please try again.');
      setSubmitting(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-base px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mb-3 inline-flex h-10 w-10 items-center justify-center rounded-md bg-brand text-sm font-semibold text-white">
            N
          </div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">
            Nomad Operations Center
          </h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Sign in with an authorized operator account.
          </p>
        </div>

        <div className="panel p-6">
          {error && (
            <div className="mb-4 rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
              {error}
            </div>
          )}

          <form onSubmit={handleEmailSignIn} className="space-y-4">
            <div>
              <label htmlFor="email" className="mb-1.5 block text-sm text-ink-secondary">
                Email
              </label>
              <input
                id="email"
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
              />
            </div>

            <div>
              <label htmlFor="password" className="mb-1.5 block text-sm text-ink-secondary">
                Password
              </label>
              <input
                id="password"
                type="password"
                required
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
              />
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-sm bg-brand py-2 text-sm font-medium text-white transition-colors hover:bg-brand-soft disabled:opacity-60"
            >
              {submitting ? 'Signing in…' : 'Sign in'}
            </button>
          </form>

          <div className="my-4 flex items-center gap-3">
            <div className="h-px flex-1 bg-base-border" />
            <span className="text-xs text-ink-muted">or</span>
            <div className="h-px flex-1 bg-base-border" />
          </div>

          <button
            type="button"
            onClick={handleGoogleSignIn}
            disabled={submitting}
            className="w-full rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary transition-colors hover:border-brand disabled:opacity-60"
          >
            Continue with Google
          </button>
        </div>

        <p className="mt-6 text-center text-xs text-ink-muted">
          Access is restricted to authorized Nomad eSports operators.
        </p>
      </div>
    </main>
  );
}
