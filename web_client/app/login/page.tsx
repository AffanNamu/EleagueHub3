'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getRedirectResult } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useDeviceMode } from '@/hooks/useDeviceMode';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { DesktopPairingView } from '@/components/auth/DesktopPairingView';
import { MobileSignInView } from '@/components/auth/MobileSignInView';
import { Loader2 } from 'lucide-react';

// Remembers which view (QR pairing vs. email/Google) was showing across a
// FULL browser navigation -- specifically the one MobileSignInView's
// "Continue with Google" button triggers via signInWithRedirect, which
// leaves the page entirely (to accounts.google.com) and comes back with
// a fresh page load. A fresh load means `override` below resets to null
// and useDeviceMode() recomputes from window.innerWidth, so without this,
// a desktop user who switched to the Google sign-in view got silently
// flipped back to the QR pairing view on return -- and since
// DesktopPairingView never calls getRedirectResult(), the just-completed
// Google sign-in was never picked up: the user just landed back on the
// QR/"sign in another way" screen as if nothing had happened, even though
// Firebase had actually signed them in.
const VIEW_OVERRIDE_KEY = 'esportlyic_login_view_override';

export default function LoginPage() {
  const router = useRouter();
  const mode = useDeviceMode();
  const [override, setOverrideState] = useState<'mobile' | 'desktop' | null>(null);
  const [resolvingRedirect, setResolvingRedirect] = useState(true);

  useEffect(() => {
    try {
      const saved = sessionStorage.getItem(VIEW_OVERRIDE_KEY);
      if (saved === 'mobile' || saved === 'desktop') setOverrideState(saved);
    } catch {
      // sessionStorage unavailable (private browsing, etc) -- falls back
      // to the device-detected mode, same as before this fix.
    }
  }, []);

  function setOverride(next: 'mobile' | 'desktop') {
    setOverrideState(next);
    try {
      sessionStorage.setItem(VIEW_OVERRIDE_KEY, next);
    } catch {}
  }

  // Runs on every load of this page regardless of which view above ends
  // up rendering -- the actual fix. MobileSignInView has its own
  // getRedirectResult() call too (for the common case where the
  // sessionStorage restore above keeps it mounted across the redirect),
  // but this is the guaranteed backstop: even if the view selection above
  // still lands on DesktopPairingView for any reason, a completed Google
  // sign-in is picked up and finished here rather than silently dropped.
  useEffect(() => {
    getRedirectResult(auth)
      .then(async (cred) => {
        if (!cred) return;
        const idToken = await cred.user.getIdToken();
        document.cookie = `session=${idToken}; path=/; max-age=${60 * 60 * 24 * 5}; Secure; SameSite=Lax`;
        router.replace('/dashboard');
      })
      .catch((err) => {
        console.error('Google redirect sign-in failed', err);
      })
      .finally(() => setResolvingRedirect(false));
  }, [router]);

  const effectiveMode = override ?? mode;

  if (effectiveMode === null || resolvingRedirect) {
    return (
      <GlassScaffold>
        <div className="flex items-center justify-center min-h-screen">
          <Loader2 className="w-8 h-8 text-brand-lime animate-spin" />
        </div>
      </GlassScaffold>
    );
  }

  if (effectiveMode === 'desktop') {
    return (
      <GlassScaffold>
        <DesktopPairingView onUseEmailInstead={() => setOverride('mobile')} />
      </GlassScaffold>
    );
  }

  return <MobileSignInView onUsePairingInstead={() => setOverride('desktop')} />;
}
