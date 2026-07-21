'use client';

import Link from 'next/link';
import { BadgeCheck } from 'lucide-react';

export function OrganizerProfileLinkButton({ masterLeagueId }: { masterLeagueId: string }) {
  return (
    <Link 
      href={`/master-leagues/${masterLeagueId}/profile`} 
      className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors" 
      title="Edit Organizer Profile" 
    >
      <BadgeCheck className="w-5 h-5 text-white" />
    </Link>
  );
}
