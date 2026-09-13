'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Loader2 } from 'lucide-react';

type ProfileStatus = 'checking' | 'complete' | 'redirecting' | 'unknown';

/**
 * Mirrors the mobile app's GoRouter redirect guard
 * (lib/core/routing/app_router.dart): any authenticated user with no
 * `users/{uid}` document gets forced to onboarding before reaching the
 * rest of the app. Web previously had the /onboarding page but nothing
 * that actually routed an incomplete-profile user into it — someone
 * could sign up and go straight to /dashboard, /leagues, etc. with no
 * profile doc ever created.
 *
 * Same tri-state semantics as mobile: a confirmed-missing doc redirects;
 * a read failure/offline state fails OPEN (renders children) rather than
 * guessing completeness or locking the user out over a transient network
 * error — mobile's own comments are explicit that completeness is never
 * inferred from anything other than the doc's real existence.
 */
export function ProfileCompletionGate({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [status, setStatus] = useState<ProfileStatus>('checking');

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (!user) {
        // Not this gate's concern — the dashboard route group's own
        // sign-in requirement handles unauthenticated visitors.
        setStatus('complete');
        return;
      }

      try {
        const snap = await getDoc(doc(db, 'users', user.uid));
        if (snap.exists()) {
          setStatus('complete');
          return;
        }
        setStatus('redirecting');
        router.replace('/onboarding');
      } catch (err) {
        console.error('[ProfileCompletionGate] profile check failed', err);
        setStatus('unknown');
      }
    });

    return () => unsubscribe();
  }, [router]);

  if (status === 'checking' || status === 'redirecting') {
    return (
      <div className="flex items-center justify-center h-screen bg-[#070B14]">
        <Loader2 className="w-8 h-8 text-brand-lime animate-spin" />
      </div>
    );
  }

  return <>{children}</>;
}
