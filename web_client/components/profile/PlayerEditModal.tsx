'use client';

import { useState, useEffect, useRef } from 'react';
import { PlayerSearchCandidate, searchPlayersWeb, resolvePhotoUrlWeb } from '@/lib/profile/playerPhotoService';
import { SquadPlayerSlot } from '@/lib/profile/teamProfileRepository';
import { Glass } from '@/components/ui/Glass';
import { Loader2, X, Search, User, Trash2, Check } from 'lucide-react';

interface PlayerEditModalProps {
  slotLabel: string;
  existing: SquadPlayerSlot | null;
  isStarting: boolean;
  onClose: () => void;
  onSave: (player: SquadPlayerSlot) => void;
  onDelete: () => void;
}

export function PlayerEditModal({ slotLabel, existing, isStarting, onClose, onSave, onDelete }: PlayerEditModalProps) {
  const [name, setName] = useState(existing?.name || '');
  const [number, setNumber] = useState(existing?.shirtNumber ? existing.shirtNumber.toString() : '');
  const [previewUrl, setPreviewUrl] = useState(existing?.photoUrl || '');
  const [resolvedUrl, setResolvedUrl] = useState(existing?.photoUrl || '');
  
  const [candidates, setCandidates] = useState<PlayerSearchCandidate[]>([]);
  const [searching, setSearching] = useState(false);
  const [resolving, setResolving] = useState(false);
  
  const debounceTimeout = useRef<NodeJS.Timeout | null>(null);
  const suppressSearch = useRef(false);

  useEffect(() => {
    if (suppressSearch.current) {
      suppressSearch.current = false;
      return;
    }

    if (resolvedUrl || previewUrl) {
      setResolvedUrl('');
      setPreviewUrl('');
    }

    if (debounceTimeout.current) clearTimeout(debounceTimeout.current);

    if (name.trim().length < 3) {
      setCandidates([]);
      setSearching(false);
      return;
    }

    setSearching(true);
    debounceTimeout.current = setTimeout(async () => {
      const results = await searchPlayersWeb(name);
      setCandidates(results);
      setSearching(false);
    }, 350);
  }, [name]);

  const selectCandidate = async (c: PlayerSearchCandidate) => {
    suppressSearch.current = true;
    setName(c.name);
    setPreviewUrl(c.previewPhotoUrl);
    setCandidates([]);
    setResolvedUrl('');

    if (!c.bestPhotoUrl) return;

    setResolving(true);
    try {
      const secureUrl = await resolvePhotoUrlWeb(c.bestPhotoUrl);
      setResolvedUrl(secureUrl);
      setPreviewUrl(secureUrl);
    } catch (err) {
      console.error(err);
    } finally {
      setResolving(false);
    }
  };

  const handleSave = () => {
    if (!name.trim()) return;
    onSave({
      playerId: existing?.playerId || `p_${Date.now()}_${slotLabel}`,
      name: name.trim(),
      position: slotLabel,
      x: existing?.x || 0,
      y: existing?.y || 0,
      isStarting,
      shirtNumber: parseInt(number) || 0,
      slotIndex: existing?.slotIndex ?? -1,
      photoUrl: resolvedUrl,
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <Glass className="w-full max-w-md bg-[#0F172A] border border-[#1E293B] rounded-3xl p-6 shadow-2xl flex flex-col max-h-[90vh]">
        
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-lg font-black text-white">{slotLabel} — {isStarting ? "Starting XI" : "Bench"}</h2>
          <button onClick={onClose} className="text-gray-500 hover:text-white"><X className="w-5 h-5"/></button>
        </div>

        <div className="flex justify-center mb-6">
          <div className="relative w-20 h-20 rounded-full bg-[#1E293B] border-2 border-gray-600 flex items-center justify-center overflow-hidden">
            {previewUrl ? <img src={previewUrl} className="w-full h-full object-cover"/> : <User className="w-8 h-8 text-gray-500"/>}
            {resolving && <div className="absolute inset-0 bg-black/50 flex items-center justify-center"><Loader2 className="w-6 h-6 text-white animate-spin"/></div>}
          </div>
        </div>

        <div className="space-y-4 flex-1 overflow-y-auto custom-scrollbar">
          <div className="relative">
            <input 
              value={name} onChange={e => setName(e.target.value)} 
              placeholder="Player name (Search real players)" 
              className="w-full bg-[#0B1221] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-[#BEF264]" 
            />
            {searching && <Loader2 className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-[#BEF264]"/>}
          </div>

          {candidates.length > 0 && (
            <div className="bg-[#0B1221] border border-[#1E293B] rounded-xl overflow-hidden max-h-60 overflow-y-auto">
              {candidates.map(c => (
                <button key={c.id} onClick={() => selectCandidate(c)} className="w-full text-left p-3 hover:bg-white/5 border-b border-[#1E293B] flex items-center gap-3 transition-colors">
                  <img src={c.previewPhotoUrl || '/placeholder.png'} className="w-10 h-10 rounded-full object-cover bg-gray-800" />
                  <div>
                    <div className="font-bold text-white text-sm">{c.name}</div>
                    <div className="text-xs text-gray-500 font-semibold">{[c.team, c.position, c.nationality].filter(Boolean).join(' • ')}</div>
                  </div>
                </button>
              ))}
            </div>
          )}

          <input 
            type="number" value={number} onChange={e => setNumber(e.target.value)} 
            placeholder="Shirt number (optional)" 
            className="w-full bg-[#0B1221] border border-[#1E293B] rounded-xl p-4 text-white outline-none focus:border-[#BEF264]" 
          />
        </div>

        <div className="flex items-center gap-3 mt-6 pt-4 border-t border-[#1E293B]">
          {existing?.name && (
            <button onClick={onDelete} className="flex-1 py-4 bg-red-500/10 text-red-500 font-black rounded-xl hover:bg-red-500/20 flex justify-center items-center gap-2">
              <Trash2 className="w-4 h-4"/> Remove
            </button>
          )}
          <button onClick={handleSave} disabled={resolving || !name} className="flex-1 py-4 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50 flex justify-center items-center gap-2 shadow-lg shadow-[#BEF264]/20">
            <Check className="w-4 h-4"/> Save
          </button>
        </div>

      </Glass>
    </div>
  );
}
