'use client';

import { useState } from 'react';
import { Shield, Pencil, Trash2, UserMinus, Check, X } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { useTeamRename, useTeamDelete, useRemoveTeamMember } from '@/hooks/useTeamRosterActions';
import type { RosterMember, TeamWithRoster } from '@/types/team';

function TeamCard({
  leagueId,
  team,
  canManage,
}: {
  leagueId: string;
  team: TeamWithRoster;
  canManage: boolean;
}) {
  const { rename, submitting: renaming, error: renameError } = useTeamRename(leagueId);
  const { remove: removeTeam, deleting, error: deleteError } = useTeamDelete(leagueId);
  const { remove: removeMember, removing, error: removeError } = useRemoveTeamMember(leagueId);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(team.name);

  async function handleRename() {
    const ok = await rename(team.id, name);
    if (ok) setEditing(false);
  }

  return (
    <div className="panel p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          {editing ? (
            <div className="flex items-center gap-2">
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                maxLength={60}
                className="rounded-sm border border-base-border bg-base-raised px-2 py-1 text-sm text-ink-primary outline-none focus:border-brand"
              />
              <button
                onClick={handleRename}
                disabled={renaming || !name.trim()}
                className="rounded-sm p-1.5 text-signal-success hover:bg-base-raised disabled:opacity-60"
                aria-label="Save name"
              >
                <Check size={15} />
              </button>
              <button
                onClick={() => {
                  setEditing(false);
                  setName(team.name);
                }}
                className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised"
                aria-label="Cancel"
              >
                <X size={15} />
              </button>
            </div>
          ) : (
            <h3 className="font-display text-sm font-semibold text-ink-primary">{team.name}</h3>
          )}
          <p className="mt-1 text-xs text-ink-muted">
            {team.roster.length} member{team.roster.length === 1 ? '' : 's'} · {team.finalPoints} pts
          </p>
        </div>
        {canManage && !editing && (
          <div className="flex items-center gap-1">
            <button
              onClick={() => setEditing(true)}
              className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
              aria-label="Rename team"
            >
              <Pencil size={14} />
            </button>
            <button
              onClick={() => removeTeam(team.id, team.name)}
              disabled={deleting === team.id}
              className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
              aria-label="Delete team"
            >
              <Trash2 size={14} />
            </button>
          </div>
        )}
      </div>

      {(renameError || deleteError || removeError) && (
        <p className="mt-2 text-xs text-signal-danger">{renameError || deleteError || removeError}</p>
      )}

      {team.roster.length > 0 ? (
        <ul className="mt-3 space-y-1.5">
          {team.roster.map((member) => (
            <li key={member.membershipId} className="flex items-center justify-between text-sm">
              <span className="text-ink-secondary">{member.displayName}</span>
              {canManage && (
                <button
                  onClick={() => removeMember(member.membershipId, member.displayName)}
                  disabled={removing === member.membershipId}
                  className="rounded-sm p-1 text-ink-muted hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                  aria-label={`Remove ${member.displayName}`}
                >
                  <UserMinus size={13} />
                </button>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 text-xs text-ink-muted">No roster members yet.</p>
      )}
    </div>
  );
}

function UnassignedSection({ members }: { members: RosterMember[] }) {
  if (members.length === 0) return null;

  return (
    <div className="panel p-5">
      <h3 className="font-display text-sm font-semibold text-ink-primary">Unassigned</h3>
      <p className="mt-1 text-xs text-ink-muted">League members not on any team.</p>
      <ul className="mt-3 space-y-1.5">
        {members.map((member) => (
          <li key={member.membershipId} className="text-sm text-ink-secondary">
            {member.displayName}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function LeagueRostersPanel({
  leagueId,
  teams,
  unassigned,
  canManage,
}: {
  leagueId: string;
  teams: TeamWithRoster[];
  unassigned: RosterMember[];
  canManage: boolean;
}) {
  if (teams.length === 0 && unassigned.length === 0) {
    return <EmptyState icon={Shield} title="No teams or members yet" />;
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {teams.map((team) => (
          <TeamCard key={team.id} leagueId={leagueId} team={team} canManage={canManage} />
        ))}
      </div>
      <UnassignedSection members={unassigned} />
    </div>
  );
}
