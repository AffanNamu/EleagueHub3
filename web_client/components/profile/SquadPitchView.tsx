'use client';

import { useRef, useState } from 'react';
import { useSquad } from '@/hooks/useTeamProfile';
import { getSlotsForFormation } from '@/lib/profile/squadLogic';
import {
  SquadData,
  SquadPlayerSlot,
  saveSquadWeb,
  updateSquadPhotoWeb,
} from '@/lib/profile/teamProfileRepository';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { PlayerEditModal } from './PlayerEditModal';
import { User, Loader2, Camera, Trash2, Plus, Star, StarOff } from 'lucide-react';

interface SquadPitchViewProps {
  userId: string;
  gameId: string;
  /** Enables tapping slots/bench to edit, plus the info/bench panel and photo upload controls. */
  isEditable?: boolean;
  /** Compact read-only rendering used inside profile preview cards. */
  isPreview?: boolean;
}

// ── Pure squad-mutation helpers ─────────────────────────────────────────────
// Mirror the equivalent `with*` methods on lib/features/profile/models/squad.dart.

function withStarterAtSlot(squad: SquadData, slotIndex: number, player: SquadPlayerSlot): SquadData {
  const normalized: SquadPlayerSlot = { ...player, isStarting: true, slotIndex };
  const withoutSlot = squad.players.filter(p => !(p.isStarting && p.slotIndex === slotIndex));
  return { ...squad, players: [...withoutSlot, normalized] };
}

function withStarterRemoved(squad: SquadData, slotIndex: number): SquadData {
  return { ...squad, players: squad.players.filter(p => !(p.isStarting && p.slotIndex === slotIndex)) };
}

function withPlayerRemoved(squad: SquadData, playerId: string): SquadData {
  return {
    ...squad,
    players: squad.players.filter(p => p.playerId !== playerId),
    captainPlayerId: squad.captainPlayerId === playerId ? '' : squad.captainPlayerId,
    viceCaptainPlayerId: squad.viceCaptainPlayerId === playerId ? '' : squad.viceCaptainPlayerId,
  };
}

function withBenchAdded(squad: SquadData, player: SquadPlayerSlot): SquadData {
  return { ...squad, players: [...squad.players, player] };
}

export function SquadPitchView({ userId, gameId, isEditable = false, isPreview = false }: SquadPitchViewProps) {
  const { squad, loading } = useSquad(userId, gameId);
  const [editingSlot, setEditingSlot] = useState<number | null>(null);
  const [editingBench, setEditingBench] = useState<'new' | SquadPlayerSlot | null>(null);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [saving, setSaving] = useState(false);
  const photoInputRef = useRef<HTMLInputElement>(null);

  if (loading || !squad) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-[#064e3b]/20">
        <div className="w-8 h-8 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const formation = squad.formation || '4-3-3';
  const slots = getSlotsForFormation(formation);
  const startingXI = squad.players.filter(p => p.isStarting);
  const bench = squad.players.filter(p => !p.isStarting);

  const persist = async (updated: SquadData) => {
    setSaving(true);
    try {
      await saveSquadWeb(userId, updated);
    } catch (err: any) {
      alert(err?.message || 'Could not save squad.');
    } finally {
      setSaving(false);
    }
  };

  const handleSlotSave = (player: SquadPlayerSlot) => {
    if (editingSlot === null) return;
    persist(withStarterAtSlot(squad, editingSlot, player));
    setEditingSlot(null);
  };

  const handleSlotDelete = () => {
    if (editingSlot === null) return;
    persist(withStarterRemoved(squad, editingSlot));
    setEditingSlot(null);
  };

  const handleBenchSave = (player: SquadPlayerSlot) => {
    if (editingBench === 'new') {
      persist(withBenchAdded(squad, player));
    } else if (editingBench) {
      persist(withBenchAdded(withPlayerRemoved(squad, editingBench.playerId), player));
    }
    setEditingBench(null);
  };

  const handleBenchDelete = () => {
    if (editingBench && editingBench !== 'new') {
      persist(withPlayerRemoved(squad, editingBench.playerId));
    }
    setEditingBench(null);
  };

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      alert('Image too large. Please select an image under 5 MB.');
      return;
    }
    setUploadingPhoto(true);
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: 'eleaguehub/squad_photos' });
      await updateSquadPhotoWeb(userId, gameId, secureUrl);
    } catch (err: any) {
      alert(err?.message || 'Upload failed.');
    } finally {
      setUploadingPhoto(false);
      if (photoInputRef.current) photoInputRef.current.value = '';
    }
  };

  const handlePhotoRemove = async () => {
    if (!confirm('Remove squad photo?')) return;
    setUploadingPhoto(true);
    try {
      await updateSquadPhotoWeb(userId, gameId, '');
    } finally {
      setUploadingPhoto(false);
    }
  };

  const setCaptain = (playerId: string) => {
    persist({
      ...squad,
      captainPlayerId: squad.captainPlayerId === playerId ? '' : playerId,
      viceCaptainPlayerId: squad.viceCaptainPlayerId === playerId ? '' : squad.viceCaptainPlayerId,
    });
  };

  const setViceCaptain = (playerId: string) => {
    persist({
      ...squad,
      viceCaptainPlayerId: squad.viceCaptainPlayerId === playerId ? '' : playerId,
      captainPlayerId: squad.captainPlayerId === playerId ? '' : squad.captainPlayerId,
    });
  };

  return (
    <div className="w-full h-full flex flex-col gap-4">
      {/* Squad photo — real team photo, distinct from per-player photos on the pitch */}
      {!isPreview && (squad.squadPhotoUrl || isEditable) && (
        <div
          className={`relative w-full ${squad.squadPhotoUrl ? 'h-40' : 'h-20'} rounded-2xl border border-white/10 overflow-hidden bg-[#0B1221] ${isEditable ? 'cursor-pointer' : ''}`}
          onClick={() => isEditable && photoInputRef.current?.click()}
        >
          {squad.squadPhotoUrl ? (
            <img src={squad.squadPhotoUrl} className="w-full h-full object-cover" alt="Squad" />
          ) : (
            <div className="w-full h-full flex flex-col items-center justify-center text-gray-500">
              <User className="w-5 h-5 mb-1" />
              <span className="text-xs font-bold">Add a photo of your squad</span>
            </div>
          )}
          {uploadingPhoto && (
            <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
              <Loader2 className="w-6 h-6 text-white animate-spin" />
            </div>
          )}
          {isEditable && squad.squadPhotoUrl && !uploadingPhoto && (
            <div className="absolute top-2 right-2 flex gap-1">
              <button onClick={(e) => { e.stopPropagation(); photoInputRef.current?.click(); }} className="p-1.5 bg-black/50 hover:bg-black/80 rounded-lg text-white">
                <Camera className="w-3.5 h-3.5" />
              </button>
              <button onClick={(e) => { e.stopPropagation(); handlePhotoRemove(); }} className="p-1.5 bg-black/50 hover:bg-red-500/80 rounded-lg text-white">
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          )}
          {isEditable && (
            <input ref={photoInputRef} type="file" accept="image/*" onChange={handlePhotoUpload} className="hidden" />
          )}
        </div>
      )}

      {/* Pitch */}
      <div
        className={`relative overflow-hidden bg-gradient-to-b from-[#064e3b] to-[#065f46] border border-[#047857] shadow-inner shadow-black/50 ${
          isPreview ? 'w-full h-full' : 'w-full aspect-[3/4] rounded-2xl'
        }`}
      >
        <div className="absolute inset-4 border-2 border-white/20 rounded-sm pointer-events-none" />
        <div className="absolute top-1/2 left-4 right-4 h-0 border-t-2 border-white/20 pointer-events-none" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-20 h-20 border-2 border-white/20 rounded-full pointer-events-none" />

        {!isPreview && (
          <div className="absolute top-2 right-2 bg-black/50 backdrop-blur-md px-3 py-1.5 rounded-lg text-xs font-black text-emerald-400 border border-emerald-500/30 z-10">
            {formation}{saving ? ' • saving…' : ''}
          </div>
        )}

        {slots.map((slot, index) => {
          const visualTop = `${(1.0 - slot.y) * 100}%`;
          const visualLeft = `${slot.x * 100}%`;
          const player = startingXI.find(p => p.slotIndex === index);
          const isCaptain = !!squad.captainPlayerId && squad.captainPlayerId === player?.playerId;
          const isVice = !!squad.viceCaptainPlayerId && squad.viceCaptainPlayerId === player?.playerId;

          return (
            <div
              key={index}
              onClick={() => isEditable && setEditingSlot(index)}
              className={`absolute -translate-x-1/2 -translate-y-1/2 flex flex-col items-center ${isEditable ? 'cursor-pointer hover:scale-110 transition-transform z-20' : ''}`}
              style={{ top: visualTop, left: visualLeft, width: isPreview ? '10%' : '14%' }}
            >
              <div
                className="relative w-full aspect-[3/4] rounded-lg border-2 overflow-hidden flex flex-col bg-gradient-to-b from-gray-800 to-gray-900 shadow-xl"
                style={{ borderColor: player ? '#BEF264' : 'rgba(255,255,255,0.3)' }}
              >
                <div className="h-[70%] w-full bg-[#111827] flex items-center justify-center">
                  {player?.photoUrl ? (
                    <img src={player.photoUrl} className="w-full h-full object-cover" />
                  ) : (
                    <User className={`w-1/2 h-1/2 ${player ? 'text-gray-400' : 'text-white/20'}`} />
                  )}
                </div>

                <div className="h-[30%] w-full bg-black/60 flex flex-col items-center justify-center px-1">
                  <span className="text-[7px] sm:text-[9px] font-black text-white truncate w-full text-center">
                    {player ? player.name.toUpperCase() : slot.label}
                  </span>
                  {player && !isPreview && (
                    <span className="text-[6px] sm:text-[8px] font-bold text-[#BEF264]">{slot.label}</span>
                  )}
                </div>

                {player?.shirtNumber ? (
                  <div className="absolute top-1 left-1 bg-[#BEF264] text-[#0F172A] text-[8px] font-black px-1 rounded-sm">
                    {player.shirtNumber}
                  </div>
                ) : null}
              </div>

              {isCaptain && (
                <div className="absolute -top-2 -right-2 w-4 h-4 bg-amber-500 rounded-full border border-white flex items-center justify-center text-[8px] font-black text-white">
                  C
                </div>
              )}
              {isVice && !isCaptain && (
                <div className="absolute -top-2 -right-2 w-4 h-4 bg-slate-400 rounded-full border border-white flex items-center justify-center text-[8px] font-black text-white">
                  V
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Manager / captaincy info + Bench — hidden in preview mode, matching mobile's SquadPitchView */}
      {!isPreview && (
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 space-y-3">
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="Manager" value={squad.managerName || '—'} />
            <InfoRow label="Team Strength" value={`${squad.teamStrength}`} />
            <InfoRow label="Captain" value={squad.players.find(p => p.playerId === squad.captainPlayerId)?.name || '—'} />
            <InfoRow label="Vice Captain" value={squad.players.find(p => p.playerId === squad.viceCaptainPlayerId)?.name || '—'} />
          </div>

          {isEditable && (
            <div className="grid grid-cols-2 gap-2 pt-2 border-t border-white/5">
              <input
                key={`manager-${squad.updatedAtMs}`}
                defaultValue={squad.managerName}
                placeholder="Manager name"
                onBlur={(e) => {
                  const v = e.target.value.trim();
                  if (v !== squad.managerName) persist({ ...squad, managerName: v });
                }}
                className="bg-[#070B14] border border-[#1E293B] rounded-lg px-3 py-2 text-xs text-white outline-none focus:border-[#BEF264]"
              />
              <input
                key={`strength-${squad.updatedAtMs}`}
                type="number"
                min={0}
                max={100}
                defaultValue={squad.teamStrength}
                placeholder="Team strength"
                onBlur={(e) => {
                  const v = Math.max(0, Math.min(100, parseInt(e.target.value, 10) || 0));
                  if (v !== squad.teamStrength) persist({ ...squad, teamStrength: v });
                }}
                className="bg-[#070B14] border border-[#1E293B] rounded-lg px-3 py-2 text-xs text-white outline-none focus:border-[#BEF264]"
              />
            </div>
          )}

          <div className="flex items-center justify-between pt-2 border-t border-white/5">
            <span className="text-xs font-black text-white">Bench ({bench.length})</span>
            {isEditable && (
              <button onClick={() => setEditingBench('new')} className="text-xs font-bold text-[#BEF264] hover:underline flex items-center gap-1">
                <Plus className="w-3.5 h-3.5" /> Add sub
              </button>
            )}
          </div>

          {bench.length === 0 ? (
            <p className="text-xs font-semibold text-gray-500">No substitutes added yet.</p>
          ) : (
            <div className="space-y-1.5">
              {bench.map((p) => {
                const isCap = p.playerId === squad.captainPlayerId;
                const isVice = p.playerId === squad.viceCaptainPlayerId;
                return (
                  <div key={p.playerId} className="flex items-center gap-2 bg-[#070B14] border border-[#1E293B] rounded-xl px-3 py-2">
                    <div className="w-7 h-7 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0">
                      {p.photoUrl ? (
                        <img src={p.photoUrl} className="w-full h-full object-cover" />
                      ) : (
                        <span className="text-[10px] font-black text-white">{p.shirtNumber || '-'}</span>
                      )}
                    </div>
                    <button
                      onClick={() => isEditable && setEditingBench(p)}
                      disabled={!isEditable}
                      className="flex-1 text-left text-xs font-bold text-white truncate disabled:cursor-default"
                    >
                      {p.name}
                    </button>
                    {isEditable && (
                      <div className="flex items-center gap-1 shrink-0">
                        <button onClick={() => setCaptain(p.playerId)} title="Make captain" className={`p-1 rounded ${isCap ? 'text-amber-400' : 'text-gray-500 hover:text-amber-400'}`}>
                          <Star className="w-3.5 h-3.5" />
                        </button>
                        <button onClick={() => setViceCaptain(p.playerId)} title="Make vice captain" className={`p-1 rounded ${isVice ? 'text-slate-300' : 'text-gray-500 hover:text-slate-300'}`}>
                          <StarOff className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {editingSlot !== null && (
        <PlayerEditModal
          slotLabel={slots[editingSlot].label}
          isStarting={true}
          existing={startingXI.find(p => p.slotIndex === editingSlot) || null}
          onClose={() => setEditingSlot(null)}
          onSave={handleSlotSave}
          onDelete={handleSlotDelete}
        />
      )}

      {editingBench !== null && (
        <PlayerEditModal
          slotLabel="SUB"
          isStarting={false}
          existing={editingBench === 'new' ? null : editingBench}
          onClose={() => setEditingBench(null)}
          onSave={handleBenchSave}
          onDelete={handleBenchDelete}
        />
      )}
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between bg-[#070B14] border border-[#1E293B] rounded-lg px-2.5 py-1.5">
      <span className="text-gray-500 font-bold">{label}</span>
      <span className="text-white font-black truncate ml-2">{value}</span>
    </div>
  );
}
