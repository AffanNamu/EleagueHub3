'use client';

import { useSquad } from '@/hooks/useTeamProfile';
import { getSlotsForFormation } from '@/lib/profile/squadLogic';
import { Shield, User } from 'lucide-react';

interface SquadPitchViewProps {
  userId: string;
  gameId: string;
  isPreview?: boolean;
}

export function SquadPitchView({ userId, gameId, isPreview = false }: SquadPitchViewProps) {
  const { squad, loading } = useSquad(userId, gameId);

  if (loading) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-[#064e3b]/20">
        <div className="w-8 h-8 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  // Use the saved formation, default to 4-3-3
  const formation = squad?.formation || '4-3-3';
  const slots = getSlotsForFormation(formation);
  
  // Extract starting XI
  const startingXI = squad?.players.filter(p => p.isStarting) || [];

  return (
    <div className="w-full h-full relative overflow-hidden bg-gradient-to-b from-[#064e3b] to-[#065f46] border border-[#047857] shadow-inner shadow-black/50">
      
      {/* ── PITCH MARKINGS ── */}
      <div className="absolute inset-4 border-2 border-white/20 rounded-sm pointer-events-none" />
      <div className="absolute top-1/2 left-4 right-4 h-0 border-t-2 border-white/20 pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-20 h-20 border-2 border-white/20 rounded-full pointer-events-none" />
      
      {/* Penalty Areas */}
      <div className="absolute top-4 left-1/2 -translate-x-1/2 w-32 h-16 border-2 border-white/20 border-t-0 pointer-events-none" />
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 w-32 h-16 border-2 border-white/20 border-b-0 pointer-events-none" />

      {/* Goal Areas */}
      <div className="absolute top-4 left-1/2 -translate-x-1/2 w-16 h-6 border-2 border-white/20 border-t-0 pointer-events-none" />
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 w-16 h-6 border-2 border-white/20 border-b-0 pointer-events-none" />

      {/* ── UI OVERLAYS ── */}
      {!isPreview && (
        <div className="absolute top-2 right-2 bg-black/50 backdrop-blur-md px-3 py-1.5 rounded-lg text-xs font-black text-emerald-400 border border-emerald-500/30">
          {formation}
        </div>
      )}

      {/* ── PLAYERS ── */}
      {slots.map((slot, index) => {
        // Map Y coordinate: Flutter Y=0 is near own goal. We render attacking upwards.
        // So visually, Defense is at the bottom (Y=1-FlutterY).
        const visualTop = `${(1.0 - slot.y) * 100}%`;
        const visualLeft = `${slot.x * 100}%`;
        
        const player = startingXI.find(p => p.slotIndex === index);

        return (
          <div 
            key={index} 
            className="absolute -translate-x-1/2 -translate-y-1/2 flex flex-col items-center"
            style={{ top: visualTop, left: visualLeft }}
          >
            <div className={`w-8 h-8 rounded-full border-2 shadow-[0_4px_10px_rgba(0,0,0,0.5)] flex items-center justify-center mb-1 overflow-hidden
              ${player ? 'bg-[#1E293B] border-emerald-400' : 'bg-emerald-900/50 border-emerald-500/30 border-dashed'}
            `}>
              {player?.photoUrl ? (
                <img src={player.photoUrl} className="w-full h-full object-cover" />
              ) : (
                <User className={`w-4 h-4 ${player ? 'text-gray-400' : 'text-emerald-300/50'}`} />
              )}
            </div>
            
            <span className="bg-black/60 px-1.5 py-0.5 rounded text-[8px] font-black text-white backdrop-blur tracking-wider shadow-sm truncate max-w-[50px] text-center">
              {player ? player.name.toUpperCase() : slot.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}
