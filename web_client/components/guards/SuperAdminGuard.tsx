'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { Loader2 } from 'lucide-react';

export function SuperAdminGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [isAuthorized, setIsAuthorized] = useState<boolean | null>(null);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (user) => {
      // The exact Super Admin UID from your Firestore Rules
      if (user && user.uid === 'QhYeBpvAoRV6j0xGigHkBth4qIG3') {
        setIsAuthorized(true);
      } else {
        setIsAuthorized(false);
        router.replace('/dashboard');
      }
    });

    return () => unsub();
  }, [router]);

  if (isAuthorized === null) {
    return (
      <div className="flex h-full items-center justify-center">
        <Loader2 className="w-8 h-8 text-brand-red animate-spin" />
      </div>
    );
  }

  if (isAuthorized === false) return null;

  return <>{children}</>;
}
