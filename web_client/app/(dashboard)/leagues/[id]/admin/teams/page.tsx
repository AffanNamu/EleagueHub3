'use client';

import { useState, useRef } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { serverTimestamp, writeBatch, collection, doc, setDoc, deleteDoc, updateDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { uploadImageToCloudinary } from '@/lib/cloudinary';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Image as ImageIcon, Shield, PlusCircle, Trash2, Edit2, Check, X } from 'lucide-react';
import { Team } from '@/types/league';
import { CsvImporter } from '@/components/leagues/CsvImporter';

export default function ManageTeamsScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // New Team State
  const [name, setName] = useState('');
  const [groupId, setGroupId] = useState('');
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Editing State
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editAdjustment, setEditAdjustment] = useState<number>(0);
  const [editGroup, setEditGroup] = useState<string>('');

  const isGroupFormat = league?.format === 'uclGroup' || league?.format === 'worldCup';

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setLogoFile(file);
      setLogoPreview(URL.createObjectURL(file));
    }
  };

  const handleAddTeam = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;

    setLoading(true);
    setError('');

    try {
      let logoUrl = '';
      if (logoFile) {
        logoUrl = await uploadImageToCloudinary(logoFile);
      }

      const teamRef = doc(collection(db, 'leagues', leagueId, 'teams'));
      
      const newTeam: Partial<Team> = {
        name: name.trim(),
        logoUrl: logoUrl,
        groupId: isGroupFormat ? groupId.trim() : undefined,
        played: 0,
        won: 0,
        drawn: 0,
        lost: 0,
        goalsFor: 0,
        goalsAgainst: 0,
        goalDifference: 0,
        basePoints: 0,
        adminAdjustment: 0,
        finalPoints: 0,
        updatedAtMs: Date.now(),
      };

      await setDoc(teamRef, newTeam);

      setName('');
      setGroupId('');
      setLogoFile(null);
      setLogoPreview(null);
    } catch (err: any) {
      console.error(err);
      setError('Failed to add team: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteTeam = async (teamId: string) => {
    if (!confirm('Are you sure you want to remove this team? This might affect existing matches.')) return;
    try {
      await deleteDoc(doc(db, 'leagues', leagueId, 'teams', teamId));
    } catch (err: any) {
      alert("Failed to delete team: " + err.message);
    }
  };

  const startEditing = (team: Team) => {
    setEditingId(team.id);
    setEditAdjustment(team.adminAdjustment || 0);
    setEditGroup(team.groupId || '');
  };

  
  const saveEdit = async (team: Team) => {
    try {
      const now = Date.now();
      const delta = editAdjustment - (team.adminAdjustment || 0);
      
      // If the adjustment didn't actually change, just close the editor
      if (delta === 0) {
        setEditingId(null);
        return;
      }

      const reason = prompt(`Reason for ${delta > 0 ? 'adding' : 'deducting'} ${Math.abs(delta)} points for ${team.name}:`);
      if (reason === null) return; // User cancelled

      const teamRef = doc(db, 'leagues', leagueId, 'teams', team.id);
      const adjustmentRef = doc(collection(db, 'leagues', leagueId, 'point_adjustments'));
      
      const basePts = team.basePoints || 0;
      const newFinalPts = basePts + editAdjustment;

      const batch = writeBatch(db);

      // 1. Update the Team document
      batch.update(teamRef, {
        groupId: isGroupFormat ? editGroup.trim() : null,
        adminAdjustment: editAdjustment,
        finalPoints: newFinalPts,
        updatedAtMs: now
      });

      // 2. Write the strict audit log (Mirrors leagues_repository_firebase.dart)
      batch.set(adjustmentRef, {
        id: adjustmentRef.id,
        teamId: team.id,
        type: delta > 0 ? 'addition' : 'deduction',
        points: Math.abs(delta),
        reason: reason.trim() || 'Admin adjustment via Web Dashboard',
        adjustedBy: auth.currentUser?.uid,
        createdAt: serverTimestamp(),
        createdAtMs: now,
      });

      await batch.commit();
      setEditingId(null);
    } catch (err: any) {
      alert("Failed to update team: " + err.message);
    }
  };


  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-brand-red flex items-center gap-2">
            <Shield className="w-6 h-6" />
            Team & Roster Management
          </h1>
          <p className="text-gray-400 mt-1">Add teams, assign groups, and manage point penalties.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Add Team Form */}
        <div className="lg:col-span-1 space-y-6">
          <CsvImporter leagueId={leagueId} isGroupFormat={isGroupFormat} onSuccess={() => {}} />
          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-4">Register New Team</h2>
            
            {error && <div className="text-xs text-brand-red mb-4">{error}</div>}

            <form onSubmit={handleAddTeam} className="space-y-4">
              <div className="flex flex-col items-center">
                <div 
                  onClick={() => fileInputRef.current?.click()}
                  className="w-24 h-24 rounded-full border-2 border-dashed border-white/20 hover:border-brand-lime bg-brand-surfaceDark flex flex-col items-center justify-center cursor-pointer transition-colors overflow-hidden relative group"
                >
                  {logoPreview ? (
                    <img src={logoPreview} alt="Preview" className="w-full h-full object-cover" />
                  ) : (
                    <ImageIcon className="w-8 h-8 text-gray-500 group-hover:text-brand-lime transition-colors" />
                  )}
                </div>
                <input type="file" ref={fileInputRef} onChange={handleImageChange} accept="image/*" className="hidden" />
                <span className="text-xs text-gray-400 mt-2">Team Logo (Optional)</span>
              </div>

              <div>
                <label className="block text-xs font-bold text-gray-300 mb-1">Team Name *</label>
                <input
                  type="text" value={name} onChange={(e) => setName(e.target.value)} required
                  placeholder="e.g. FC Barcelona"
                  className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime transition-colors text-sm"
                />
              </div>

              {isGroupFormat && (
                <div>
                  <label className="block text-xs font-bold text-gray-300 mb-1">Assign to Group (e.g. Group A)</label>
                  <input
                    type="text" value={groupId} onChange={(e) => setGroupId(e.target.value)}
                    placeholder="Group A"
                    className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime transition-colors text-sm"
                  />
                </div>
              )}

              <button
                type="submit"
                disabled={loading || !name.trim()}
                className="w-full py-3 bg-brand-lime text-brand-navy font-bold rounded-lg hover:bg-brand-lime/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2 text-sm"
              >
                {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <PlusCircle className="w-4 h-4" />}
                Add Team
              </button>
            </form>
          </Glass>
        </div>

        {/* Existing Teams List */}
        <div className="lg:col-span-2">
          <Glass className="p-6 h-full">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-lg font-bold text-white">Registered Roster</h2>
              <span className="text-sm font-normal text-brand-lime bg-brand-lime/10 px-3 py-1.5 rounded-md border border-brand-lime/20">
                {teams.length} / {league?.maxTeams || '∞'} Teams
              </span>
            </div>

            {teamsLoading ? (
              <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 text-brand-lime animate-spin" /></div>
            ) : teams.length === 0 ? (
              <div className="text-center py-10 text-gray-500">
                <Shield className="w-12 h-12 mx-auto mb-3 opacity-50" />
                <p>No teams added yet.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {/* Table Header */}
                <div className="flex items-center justify-between px-3 pb-2 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">
                  <div className="flex-1">Team</div>
                  {isGroupFormat && <div className="w-20 text-center">Group</div>}
                  <div className="w-20 text-center">Base Pts</div>
                  <div className="w-24 text-center">Adjustment</div>
                  <div className="w-20 text-right pr-2">Actions</div>
                </div>

                {teams.map((team) => {
                  const isEditing = editingId === team.id;
                  
                  return (
                    <div key={team.id} className={`flex items-center justify-between p-3 border rounded-xl transition-colors ${isEditing ? 'bg-brand-lime/5 border-brand-lime/30' : 'bg-brand-surface border-white/5 hover:bg-white/5'}`}>
                      
                      {/* Team Info */}
                      <div className="flex items-center gap-3 flex-1 min-w-0 pr-4">
                        {team.logoUrl ? (
                          <img src={team.logoUrl} alt={team.name} className="w-8 h-8 rounded-full object-cover shrink-0" />
                        ) : (
                          <div className="w-8 h-8 rounded-full bg-brand-surfaceDark flex items-center justify-center shrink-0">
                            <Shield className="w-4 h-4 text-gray-400" />
                          </div>
                        )}
                        <span className="font-bold text-white truncate text-sm">{team.name}</span>
                      </div>
                      
                      {/* Group Assignment */}
                      {isGroupFormat && (
                        <div className="w-20 text-center">
                          {isEditing ? (
                            <input 
                              type="text" value={editGroup} onChange={(e) => setEditGroup(e.target.value)}
                              className="w-full bg-brand-navy border border-white/10 rounded px-2 py-1 text-center text-xs text-white"
                            />
                          ) : (
                            <span className="text-xs font-bold text-gray-400 bg-white/5 px-2 py-1 rounded">{team.groupId || '-'}</span>
                          )}
                        </div>
                      )}

                      {/* Base Points (Read-only) */}
                      <div className="w-20 text-center font-mono text-sm text-gray-400">
                        {team.basePoints || 0}
                      </div>

                      {/* Admin Adjustment */}
                      <div className="w-24 text-center">
                        {isEditing ? (
                          <input 
                            type="number" value={editAdjustment} onChange={(e) => setEditAdjustment(parseInt(e.target.value) || 0)}
                            className="w-full bg-brand-navy border border-white/10 rounded px-2 py-1 text-center text-xs text-white"
                          />
                        ) : (
                          <span className={`text-sm font-black tabular-nums ${team.adminAdjustment! > 0 ? 'text-brand-lime' : team.adminAdjustment! < 0 ? 'text-brand-red' : 'text-gray-500'}`}>
                            {team.adminAdjustment! > 0 ? `+${team.adminAdjustment}` : team.adminAdjustment || 0}
                          </span>
                        )}
                      </div>
                      
                      {/* Actions */}
                      <div className="w-20 flex justify-end gap-1">
                        {isEditing ? (
                          <>
                            <button onClick={() => saveEdit(team)} className="p-1.5 text-brand-lime hover:bg-brand-lime/10 rounded-md transition-colors"><Check className="w-4 h-4" /></button>
                            <button onClick={() => setEditingId(null)} className="p-1.5 text-gray-400 hover:text-white hover:bg-white/10 rounded-md transition-colors"><X className="w-4 h-4" /></button>
                          </>
                        ) : (
                          <>
                            <button onClick={() => startEditing(team)} className="p-1.5 text-gray-400 hover:text-brand-lime hover:bg-brand-lime/10 rounded-md transition-colors"><Edit2 className="w-4 h-4" /></button>
                            <button onClick={() => handleDeleteTeam(team.id)} className="p-1.5 text-gray-400 hover:text-brand-red hover:bg-brand-red/10 rounded-md transition-colors"><Trash2 className="w-4 h-4" /></button>
                          </>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Glass>
        </div>
      </div>
    </div>
  );
}
