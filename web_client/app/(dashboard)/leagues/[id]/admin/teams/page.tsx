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
        setError('No user found with that uid, or the uid is too short (short share-codes are not yet supported on web).');
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
    if (!confirm('Are you sure you want to remove this team? This might affect existing matches.')) return;
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
          // Auto-assign groups deterministically, 4 teams per group,
          // mirroring the Flutter app's auto-assign behavior for World Cup.
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
        alert('Swiss-format fixture generation is not yet available on web. Please use the Flutter app to generate Swiss fixtures for this league.');
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
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-brand-red flex items-center gap-2">
            <Shield className="w-6 h-6" />
            Team & Roster Management
          </h1>
          <p className="text-gray-400 mt-1 text-sm">Add real participants, assign groups, and manage point penalties.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-6">
          <CsvImporter leagueId={leagueId} isGroupFormat={isGroupFormat} allowedGroups={allowedGroups} onSuccess={() => {}} />

          <Glass className="p-6">
            <h2 className="text-lg font-bold text-white mb-1">Add Participant</h2>
            <p className="text-xs text-gray-400 mb-4">Enter the participant's full uid to register their team.</p>

            {error && (
              <div className="text-xs text-brand-red mb-4 flex items-start gap-2 bg-brand-red/10 border border-brand-red/20 rounded-lg p-3">
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
                  className="flex-1 bg-brand-surface border border-white/10 rounded-lg p-3 text-white focus:border-brand-lime transition-colors text-sm"
                />
                <button
                  onClick={handleLookup}
                  disabled={resolving || !lookupValue.trim()}
                  className="px-4 bg-white/10 text-white text-sm font-bold rounded-lg hover:bg-white/20 disabled:opacity-50 transition-colors"
                >
                  {resolving ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Find'}
                </button>
              </div>

              {resolved && (
                <div className="p-3 bg-brand-lime/10 border border-brand-lime/30 rounded-xl flex items-center gap-3">
                  {resolved.photoUrl ? (
                    <img src={resolved.photoUrl} alt="" className="w-9 h-9 rounded-full object-cover" />
                  ) : (
                    <div className="w-9 h-9 rounded-full bg-brand-surfaceDark flex items-center justify-center">
                      <Shield className="w-4 h-4 text-gray-400" />
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-white truncate">{resolved.teamName}</p>
                    <p className="text-[11px] text-gray-400 truncate">{resolved.userId}</p>
                  </div>
                </div>
              )}

              {isGroupFormat && resolved && (
                <div>
                  <label className="block text-xs font-bold text-gray-300 mb-1">Assign to Group</label>
                  <select
                    value={selectedGroup}
                    onChange={(e) => setSelectedGroup(e.target.value)}
                    className="w-full bg-brand-surface border border-white/10 rounded-lg p-3 text-white text-sm focus:border-brand-lime"
                  >
                    {allowedGroups.map((g) => <option key={g} value={g} className="text-slate-900">{g}</option>)}
                  </select>
                </div>
              )}

              <button
                onClick={handleAddTeam}
                disabled={adding || !resolved}
                className="w-full py-3 bg-brand-lime text-brand-navy font-bold rounded-lg hover:bg-brand-lime/90 transition-all disabled:opacity-50 flex items-center justify-center gap-2 text-sm"
              >
                {adding ? <Loader2 className="w-4 h-4 animate-spin" /> : <PlusCircle className="w-4 h-4" />}
                Add Team
              </button>
            </div>
          </Glass>

          <Glass className="p-6">
            <h3 className="text-sm font-bold text-white mb-2">Generate Fixtures</h3>
            <p className="text-xs text-gray-400 mb-4">
              {teams.length} / {maxTeams} teams {requiredCountReached ? '— ready to generate.' : '— add more teams to unlock.'}
            </p>
            <button
              onClick={handleGenerateFixtures}
              disabled={generating || !requiredCountReached}
              className="w-full py-3 bg-white/10 border border-brand-lime/40 text-brand-lime font-bold rounded-lg hover:bg-brand-lime/10 transition-all disabled:opacity-40 flex items-center justify-center gap-2 text-sm"
            >
              {generating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Wand2 className="w-4 h-4" />}
              Generate Fixtures
            </button>
          </Glass>
        </div>

        <div className="lg:col-span-2">
          <Glass className="p-4 sm:p-6 h-full">
            <div className="flex justify-between items-center mb-6 flex-wrap gap-2">
              <h2 className="text-lg font-bold text-white">Registered Roster</h2>
              <span className="text-sm font-normal text-brand-lime bg-brand-lime/10 px-3 py-1.5 rounded-md border border-brand-lime/20">
                {teams.length} / {maxTeams || '∞'} Teams
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
              <div className="space-y-3 overflow-x-auto">
                <div className="hidden sm:flex items-center justify-between px-3 pb-2 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5 min-w-[560px]">
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
                    <div key={team.id} className={`flex items-center justify-between p-3 border rounded-xl transition-colors gap-2 min-w-[560px] sm:min-w-0 ${isEditing ? 'bg-brand-lime/5 border-brand-lime/30' : 'bg-brand-surface border-white/5 hover:bg-white/5'}`}>
                      <div className="flex items-center gap-3 flex-1 min-w-0 pr-4">
                        {imgUrl ? (
                          <img src={imgUrl} alt={team.name} className="w-8 h-8 rounded-full object-cover shrink-0" />
                        ) : (
                          <div className="w-8 h-8 rounded-full bg-brand-surfaceDark flex items-center justify-center shrink-0">
                            <Shield className="w-4 h-4 text-gray-400" />
                          </div>
                        )}
                        <span className="font-bold text-white truncate text-sm">{team.name}</span>
                      </div>

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

                      <div className="w-20 text-center font-mono text-sm text-gray-400">
                        {team.basePoints || 0}
                      </div>

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
