'use client';

import React, { useState } from 'react';
import { Share, Check } from 'lucide-react';

interface ShareMatchProps {
  leagueName: string;
  homeTeam: string;
  awayTeam: string;
  homeScore?: number;
  awayScore?: number;
}

export const ShareMatchButton: React.FC<ShareMatchProps> = ({ 
  leagueName, homeTeam, awayTeam, homeScore = 0, awayScore = 0 
}) => {
  const [copied, setCopied] = useState(false);

  const handleShare = async () => {
    // Matches MatchSheetService.generateTextReport from Dart
    const report = `🏆 ${leagueName}\n⚽ Match Result:\n${homeTeam} [${homeScore}] - [${awayScore}] ${awayTeam}\n\nCheck out the full standings on eSportlyic!`;
    const title = `Match Result: ${homeTeam} vs ${awayTeam}`;

    if (navigator.share) {
      try {
        await navigator.share({
          title: title,
          text: report,
        });
      } catch (err) {
        console.log('Share rejected or failed', err);
      }
    } else {
      // Fallback to clipboard if Web Share API is unavailable (e.g., desktop browsers)
      await navigator.clipboard.writeText(report);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <button 
      onClick={handleShare}
      className="flex items-center gap-2 px-4 py-2 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 transition-colors shadow-lg shadow-brand-lime/20 text-xs sm:text-sm uppercase tracking-wider"
    >
      {copied ? <Check className="w-4 h-4" /> : <Share className="w-4 h-4" />}
      {copied ? 'Copied!' : 'Share Match'}
    </button>
  );
};
