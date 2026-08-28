'use client';

import { useState, useRef, useMemo } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, setDoc, deleteDoc, writeBatch, collection, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Shield, PlusCircle, Trash2, Edit2, Check, X, AlertTriangle, Wand2 } from 'lucide-react';
import { Team } from '@/types/league';
import { CsvImporter } from '@/components/leagues/CsvImporter';
import { resolveTeamParticipant, ResolvedUserProfile } from '@/lib/services/userProfileRepository';
import { FixtureGenerator } from '@/lib/algorithms/fixtureGenerator';

const GROUPS_ALL = ['Group A','Group B','Group C','Group D','Group E','Group F','Group G','Group H','Group I','Group J','Group K','Group L'];

function worldCupTeamCount(fmt?: string): number {
  return fmt === 'fifa2026' ? 48 : 32;
}
function worldCupGroupCount(fmt?: string): number {
  return fmt === 'fifa2026' ? 12 : 8;
}

export default function ManageTeamsScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  const inputRef = useRef<HTMLInputElement>(null);

  const [lookupValue, setLookupValue] = useState('');
  const [resolving, setResolving] = useState(false);
  const [resolved, setResolved] = useState<ResolvedUserProfile | null>(null);
  const [selectedGroup, setSelectedGroup] = useState('Group A');
  const [error, setError] = useState('');
  const [adding, setAdding] = useState(false);
  const [generating, setGenerating] = useState(false);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editAdjustment, setEditAdjustment] = useState<number>(0);
  const [editGroup, setEditGroup] = useState<string>('');

  const isGroupFormat = league?.format === 'uclGroup';
  const isWorldCup = league?.format === 'worldCup';
  const isSwiss = league?.format === 'uclSwiss';
  const isClassic = league?.format === 'classic';

  const maxTeams = useMemo(() => {
    if (!league) return 0;
    if (isGroupFormat) return 32;
    if (isSwiss) return 36;
    if (isWorldCup) return worldCupTeamCount(league.settings?.worldCupFormat);
    return Math.min(Math.max(league.maxTeams || 20, 2), 40);
  }, [league, isGroupFormat, isSwiss, isWorldCup]);

  const allowedGroups = useMemo(() => {
    if (isGroupFormat) return teams.length > 16 ? GROUPS_ALL.slice(0, 8) : GROUPS_ALL.slice(0, 4);
    if (isWorldCup) return GROUPS_ALL.slice(0, worldCupGroupCount(league?.settings?.worldCupFormat));
    return [];
  }, [isGroupFormat, isWorldCup, teams.length, league]);

  const requiredCountReached = useMemo(() => {
    const n = teams.length;
    if (isGroupFormat) return n === 16 || n === 32;
    if (isSwiss) return n === 18 || n === 36;
    if (isWorldCup) return n === maxTeams;
    return n >= 2;
  }, [teams.length, isGroupFormat, isSwiss, isWorldCup, maxTeams]);

  const handleLookup = async () => {
    setError('');
    setResolved(null);
    const val = lookupValue.trim();
    if (!val) return;
    setResolving(true);
    try {
      const profile = await resolveTeamParticipant(val);
      if (!profile) {
        setError('No user found with that uid, or the uid is too short.');
        return;
      }
      if (teams.some((t) => t.id === profile.userId)) {
        setError('This user already has a team in this league.');
        return;
      }
      setResolved(profile);
    } catch (err: any) {
      setError(err.message || 'Lookup failed');
    } finally {
      setResolving(false);
    }
  };

  const handleAddTeam = async () => {
    if (!resolved) return;
    if (teams.length >= maxTeams) {
      setError(`Maximum ${maxTeams} teams reached for this format.`);
      return;
    }
    setAdding(true);
    setError('');
    try {
      const now = Date.now();
      const teamRef = doc(db, 'leagues', leagueId, 'teams', resolved.userId);
      const newTeam: Partial<Team> = {
        id: resolved.userId,
        leagueId,
        name: resolved.teamName,
        ownerId: resolved.userId,
        teamImageUrl: resolved.photoUrl,
        groupId: isGroupFormat ? selectedGroup : undefined,
        played: 0, won: 0, drawn: 0, lost: 0,
        goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
        basePoints: 0, adminAdjustment: 0, finalPoints: 0,
        updatedAtMs: now,
      };
      await setDoc(teamRef, newTeam, { merge: true });
      setLookupValue('');
      setResolved(null);
    } catch (err: any) {
      setError('Failed to add team: ' + err.message);
    } finally {
      setAdding(false);
    }
  };

  const handleDeleteTeam = async (teamId: string) => {
    if (!confirm('Are you sure you want to remove this team?')) return;
    try {
      await deleteDoc(doc(db, 'leagues', leagueId, 'teams', teamId));
    } catch (err: any) {
      alert('Failed to delete team: ' + err.message);
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

      if (delta === 0 && editGroup === (team.groupId || '')) {
        setEditingId(null);
        return;
      }

      let reasonNote = '';
      if (delta !== 0) {
        const reason = prompt(`Reason for ${delta > 0 ? 'adding' : 'deducting'} ${Math.abs(delta)} points for ${team.name}:`);
        if (reason === null) return;
        reasonNote = reason.trim() || 'Admin adjustment via Web Dashboard';
      }

      const teamRef = doc(db, 'leagues', leagueId, 'teams', team.id);
      const basePts = team.basePoints || 0;
      const newFinalPts = basePts + editAdjustment;

      const batch = writeBatch(db);
      batch.update(teamRef, {
        groupId: isGroupFormat ? editGroup.trim() : null,
        adminAdjustment: editAdjustment,
        finalPoints: newFinalPts,
        updatedAtMs: now,
      });

      if (delta !== 0) {
        const adjustmentRef = doc(collection(db, 'leagues', leagueId, 'point_adjustments'));
        batch.set(adjustmentRef, {
          id: adjustmentRef.id,
          teamId: team.id,
          type: delta > 0 ? 'addition' : 'deduction',
          points: Math.abs(delta),
          reason: reasonNote,
          adjustedBy: auth.currentUser?.uid,
          createdAt: serverTimestamp(),
          createdAtMs: now,
        });
      }

      await batch.commit();
      setEditingId(null);
    } catch (err: any) {
      alert('Failed to update team: ' + err.message);
    }
  };

  const handleGenerateFixtures = async () => {
    if (!league) return;
    if (!requiredCountReached) {
      alert(`Cannot generate fixtures: team count does not match required amount for this format.`);
      return;
    }
    setGenerating(true);
    try {
      let fixtures: any[] = [];

      if (isClassic) {
        fixtures = FixtureGenerator.generateClassicLeagueFixtures(league, teams);
      } else if (isGroupFormat || isWorldCup) {
        const groupCount = isWorldCup ? worldCupGroupCount(league.settings?.worldCupFormat) : (teams.length > 16 ? 8 : 4);
        const validGroups = new Set(GROUPS_ALL.slice(0, groupCount));
        const structureValid =
          teams.every((t) => t.groupId && validGroups.has(t.groupId)) &&
          new Set(teams.map((t) => t.groupId)).size === groupCount;

        let teamsForGeneration = teams;
        if (!structureValid) {
          const sorted = [...teams].sort((a, b) => a.id.localeCompare(b.id));
          const now = Date.now();
          const batch = writeBatch(db);
          const groups = GROUPS_ALL.slice(0, groupCount);
          teamsForGeneration = sorted.map((t, i) => {
            const groupId = groups[Math.floor(i / 4)];
            const teamRef = doc(db, 'leagues', leagueId, 'teams', t.id);
            batch.update(teamRef, { groupId, updatedAtMs: now });
            return { ...t, groupId };
          });
          await batch.commit();
        }

        fixtures = FixtureGenerator.generateGroupStage(league, teamsForGeneration);
      } else if (isSwiss) {
        alert('Swiss-format fixture generation is not yet available on web. Please use the Flutter app.');
        return;
      }

      if (fixtures.length === 0) {
        alert('Failed to generate fixtures.');
        return;
      }

      const batch = writeBatch(db);
      const matchesRef = collection(db, 'leagues', leagueId, 'matches');
      for (const f of fixtures) {
        const ref = doc(matchesRef, f.id);
        batch.set(ref, f);
      }
      await batch.commit();

      alert(`Generated ${fixtures.length} fixtures.`);
      router.push(`/leagues/${leagueId}`);
    } catch (err: any) {
      alert('Failed to generate fixtures: ' + err.message);
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-10 px-4 sm:px-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
            <Shield className="w-6 h-6 text-[#BEF264]" />
            Team & Roster Management
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Add participants, assign groups, and manage point penalties.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-6">
          <CsvImporter leagueId={leagueId} isGroupFormat={isGroupFormat} allowedGroups={allowedGroups} onSuccess={() => {}} />

          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h2 className="text-lg font-black text-white mb-1">Add Participant</h2>
            <p className="text-xs font-semibold text-gray-400 mb-4">Enter the participant's full uid to register their team.</p>

            {error && (
              <div className="text-xs font-bold text-red-500 mb-4 flex items-start gap-2 bg-red-500/10 border border-red-500/20 rounded-xl p-3">
                <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" /> {error}
              </div>
            )}

            <div className="space-y-4">
              <div className="flex gap-2">
                <input
                  ref={inputRef}
                  type="text"
                  value={lookupValue}
                  onChange={(e) => { setLookupValue(e.target.value); setResolved(null); }}
                  onKeyDown={(e) => e.key === 'Enter' && handleLookup()}
                  placeholder="Participant uid"
                  className="flex-1 bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-sm font-bold text-white focus:border-[#BEF264] outline-none transition-colors"
                />
                <button
                  onClick={handleLookup}
                  disabled={resolving || !lookupValue.trim()}
                  className="px-5 bg-[#1E293B] text-white text-xs font-black rounded-xl hover:bg-[#2A3A52] disabled:opacity-50 transition-colors"
                >
                  {resolving ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Find'}
                </button>
              </div>

              {resolved && (
                <div className="p-4 bg-[#BEF264]/10 border border-[#BEF264]/30 rounded-2xl flex items-center gap-3">
                  {resolved.photoUrl ? (
                    <img src={resolved.photoUrl} alt="" className="w-10 h-10 rounded-full object-cover" />
                  ) : (
                    <div className="w-10 h-10 rounded-full bg-[#1E293B] flex items-center justify-center">
                      <Shield className="w-5 h-5 text-gray-400" />
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-black text-white truncate">{resolved.teamName}</p>
                    <p className="text-[11px] font-bold text-gray-400 truncate">{resolved.userId}</p>
                  </div>
                </div>
              )}

              {isGroupFormat && resolved && (
                <div>
                  <label className="block text-xs font-bold text-gray-300 mb-2">Assign to Group</label>
                  <select
                    value={selectedGroup}
                    onChange={(e) => setSelectedGroup(e.target.value)}
                    className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3 text-sm font-bold text-white focus:border-[#BEF264] outline-none"
                  >
                    {allowedGroups.map((g) => <option key={g} value={g}>{g}</option>)}
                  </select>
                </div>
              )}

              <button
                onClick={handleAddTeam}
                disabled={adding || !resolved}
                className="w-full py-3.5 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 text-sm shadow-lg shadow-[#BEF264]/10"
              >
                {adding ? <Loader2 className="w-4 h-4 animate-spin" /> : <PlusCircle className="w-4 h-4" />}
                Add Team
              </button>
            </div>
          </div>

          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
            <h3 className="text-base font-black text-white mb-2">Generate Fixtures</h3>
            <p className="text-xs font-semibold text-gray-400 mb-4">
              {teams.length} / {maxTeams} teams {requiredCountReached ? '— ready to generate.' : '— add more teams to unlock.'}
            </p>
            <button
              onClick={handleGenerateFixtures}
              disabled={generating || !requiredCountReached}
              className="w-full py-3.5 bg-[#1E293B] border border-[#BEF264]/40 text-[#BEF264] font-black rounded-xl hover:bg-[#1E293B]/80 transition-all disabled:opacity-40 flex items-center justify-center gap-2 text-xs"
            >
              {generating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Wand2 className="w-4 h-4" />}
              Generate Fixtures
            </button>
          </div>
        </div>

        <div className="lg:col-span-2">
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl h-full flex flex-col">
            <div className="flex justify-between items-center mb-6 flex-wrap gap-2">
              <h2 className="text-lg font-black text-white">Registered Roster</h2>
              <span className="text-xs font-black text-[#BEF264] bg-[#BEF264]/10 px-3 py-1.5 rounded-xl border border-[#BEF264]/20">
                {teams.length} / {maxTeams || '∞'} Teams
              </span>
            </div>

            {teamsLoading ? (
              <div className="flex justify-center py-12"><Loader2 className="w-8 h-8 text-[#BEF264] animate-spin" /></div>
            ) : teams.length === 0 ? (
              <div className="text-center py-16 text-gray-500">
                <Shield className="w-12 h-12 mx-auto mb-3 opacity-30 text-[#BEF264]" />
                <p className="text-sm font-bold">No teams added yet.</p>
              </div>
            ) : (
              <div className="space-y-3 overflow-x-auto flex-1">
                <div className="hidden sm:flex items-center justify-between px-4 pb-2 text-[10px] font-black text-gray-400 uppercase tracking-widest border-b border-[#1E293B] min-w-[560px]">
                  <div className="flex-1">Team</div>
                  {isGroupFormat && <div className="w-20 text-center">Group</div>}
                  <div className="w-20 text-center">Base Pts</div>
                  <div className="w-24 text-center">Adjustment</div>
                  <div className="w-20 text-right pr-2">Actions</div>
                </div>

                {teams.map((team) => {
                  const isEditing = editingId === team.id;
                  const imgUrl = team.teamImageUrl || team.logoUrl;

                  return (
                    <div key={team.id} className={`flex items-center justify-between p-4 border rounded-2xl transition-colors gap-2 min-w-[560px] sm:min-w-0 ${isEditing ? 'bg-[#BEF264]/5 border-[#BEF264]/30' : 'bg-[#070B14] border-[#1E293B]'}`}>
                      <div className="flex items-center gap-3 flex-1 min-w-0 pr-4">
                        {imgUrl ? (
                          <img src={imgUrl} alt={team.name} className="w-9 h-9 rounded-full object-cover shrink-0 border border-white/10" />
                        ) : (
                          <div className="w-9 h-9 rounded-full bg-[#1E293B] flex items-center justify-center shrink-0 border border-white/10">
                            <Shield className="w-4 h-4 text-gray-400" />
                          </div>
                        )}
                        <span className="font-black text-white truncate text-sm">{team.name}</span>
                      </div>

                      {isGroupFormat && (
                        <div className="w-20 text-center">
                          {isEditing ? (
                            <input
                              type="text" value={editGroup} onChange={(e) => setEditGroup(e.target.value)}
                              className="w-full bg-[#0B1221] border border-white/10 rounded-lg px-2 py-1 text-center text-xs font-bold text-white outline-none focus:border-[#BEF264]"
                            />
                          ) : (
                            <span className="text-xs font-black text-gray-300 bg-[#1E293B] px-2.5 py-1 rounded-lg">{team.groupId || '-'}</span>
                          )}
                        </div>
                      )}

                      <div className="w-20 text-center font-mono text-sm font-bold text-gray-400">
                        {team.basePoints || 0}
                      </div>

                      <div className="w-24 text-center">
                        {isEditing ? (
                          <input
                            type="number" value={editAdjustment} onChange={(e) => setEditAdjustment(parseInt(e.target.value) || 0)}
                            className="w-full bg-[#0B1221] border border-white/10 rounded-lg px-2 py-1 text-center text-xs font-bold text-white outline-none focus:border-[#BEF264]"
                          />
                        ) : (
                          <span className={`text-sm font-black tabular-nums ${team.adminAdjustment! > 0 ? 'text-[#BEF264]' : team.adminAdjustment! < 0 ? 'text-red-500' : 'text-gray-500'}`}>
                            {team.adminAdjustment! > 0 ? `+${team.adminAdjustment}` : team.adminAdjustment || 0}
                          </span>
                        )}
                      </div>

                      <div className="w-20 flex justify-end gap-1">
                        {isEditing ? (
                          <>
                            <button onClick={() => saveEdit(team)} className="p-2 text-[#BEF264] hover:bg-[#BEF264]/10 rounded-xl transition-colors"><Check className="w-4 h-4" /></button>
                            <button onClick={() => setEditingId(null)} className="p-2 text-gray-400 hover:text-white hover:bg-white/10 rounded-xl transition-colors"><X className="w-4 h-4" /></button>
                          </>
                        ) : (
                          <>
                            <button onClick={() => startEditing(team)} className="p-2 text-gray-400 hover:text-[#BEF264] hover:bg-[#BEF264]/10 rounded-xl transition-colors"><Edit2 className="w-4 h-4" /></button>
                            <button onClick={() => handleDeleteTeam(team.id)} className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-500/10 rounded-xl transition-colors"><Trash2 className="w-4 h-4" /></button>
                          </>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
