'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useDeviceMode } from '@/hooks/useDeviceMode';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { DesktopPairingView } from '@/components/auth/DesktopPairingView';
import { Loader2 } from 'lucide-react';

export default function PairingPage() {
  const router = useRouter();
  const mode = useDeviceMode();

  useEffect(() => {
    if (mode === 'mobile') {
      router.replace('/login');
    }
  }, [mode, router]);

  if (mode === null || mode === 'mobile') {
    return (
      <GlassScaffold>
        <div className="flex items-center justify-center min-h-screen">
          <Loader2 className="w-8 h-8 text-brand-lime animate-spin" />
        </div>
      </GlassScaffold>
    );
  }

  return (
    <GlassScaffold>
      <DesktopPairingView onUseEmailInstead={() => router.push('/login')} />
    </GlassScaffold>
  );
}
