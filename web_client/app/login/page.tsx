'use client';

import { useState } from 'react';
import { useDeviceMode } from '@/hooks/useDeviceMode';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { DesktopPairingView } from '@/components/auth/DesktopPairingView';
import { MobileSignInView } from '@/components/auth/MobileSignInView';
import { Loader2 } from 'lucide-react';

export default function LoginPage() {
  const mode = useDeviceMode();
  const [override, setOverride] = useState<'mobile' | 'desktop' | null>(null);

  const effectiveMode = override ?? mode;

  if (effectiveMode === null) {
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
