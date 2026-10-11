'use client';

import { useState } from 'react';
import { Shield, Pencil, Trash2, UserMinus, Check, X, Link2Off, UserPlus } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { Badge } from '@/components/ui/Badge';
import {
  useTeamRename,
  useTeamDelete,
  useRemoveTeamMember,
  useRevokeClaim,
  useAssignMemberToTeam,
} from '@/hooks/useTeamRosterActions';
import type { RosterMember, TeamClaim, TeamWithRoster } from '@/types/team';

function formatDate(ms: number): string {
  if (!ms) return '—';
  return new Date(ms).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function ClaimRow({
  leagueId,
  teamId,
  teamName,
  claim,
  canManage,
}: {
  leagueId: string;
  teamId: string;
  teamName: string;
  claim: TeamClaim;
  canManage: boolean;
}) {
  const { revoke, revoking, error } = useRevokeClaim(leagueId);

  return (
    <li className="flex items-center justify-between gap-2 text-xs">
      <span className="text-ink-secondary">
        {claim.status === 'claimed' && `Claimed by ${claim.consumedByDisplayName ?? claim.consumedByUserId} on ${formatDate(claim.consumedAtMs ?? 0)}`}
        {claim.status === 'revoked' && `Revoked (created ${formatDate(claim.createdAtMs)})`}
        {claim.status === 'pending' && `Pending · created ${formatDate(claim.createdAtMs)} · expires ${formatDate(claim.expiresAtMs)}`}
      </span>
      {canManage && claim.status === 'pending' && (
        <button
          onClick={() => revoke(teamId, claim.token, teamName)}
          disabled={revoking === claim.token}
          className="flex items-center gap-1 rounded-sm px-1.5 py-0.5 text-ink-muted hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
        >
          <Link2Off size={12} />
          Revoke
        </button>
      )}
      {error && <span className="text-signal-danger">{error}</span>}
    </li>
  );
}

// Absent participantType means "registered" (every pre-existing team) --
// see Team.participantType* in lib/features/leagues/models/team.dart.
function ParticipantBadge({ team }: { team: TeamWithRoster }) {
  if ((team.participantType ?? 'registered') !== 'external') return null;

  switch (team.claimStatus) {
    case 'claimed':
      return <Badge tone="success">Claimed</Badge>;
    case 'claim_pending':
      return <Badge tone="warning">Claim Pending</Badge>;
    case 'revoked':
      return <Badge tone="neutral">Revoked</Badge>;
    case 'expired':
      return <Badge tone="neutral">Expired</Badge>;
    default:
      return <Badge tone="neutral">External · Not Claimed</Badge>;
  }
}

function TeamCard({
  leagueId,
  team,
  claims,
  canManage,
}: {
  leagueId: string;
  team: TeamWithRoster;
  claims: TeamClaim[];
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
            <div className="flex items-center gap-2">
              <h3 className="font-display text-sm font-semibold text-ink-primary">{team.name}</h3>
              <ParticipantBadge team={team} />
            </div>
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

      {claims.length > 0 && (
        <div className="mt-3 border-t border-base-border pt-3">
          <p className="text-xs font-medium text-ink-primary">Claim links</p>
          <ul className="mt-1.5 space-y-1">
            {claims.map((claim) => (
              <ClaimRow
                key={claim.token}
                leagueId={leagueId}
                teamId={team.id}
                teamName={team.name}
                claim={claim}
                canManage={canManage}
              />
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function UnassignedMemberRow({
  leagueId,
  member,
  teams,
  canManage,
}: {
  leagueId: string;
  member: RosterMember;
  teams: TeamWithRoster[];
  canManage: boolean;
}) {
  const { assign, assigning, error } = useAssignMemberToTeam(leagueId);
  const [selectedTeamId, setSelectedTeamId] = useState(teams[0]?.id ?? '');

  async function handleAssign() {
    if (!selectedTeamId) return;
    const team = teams.find((t) => t.id === selectedTeamId);
    if (!team) return;
    if (!confirm(`Assign ${member.displayName} to ${team.name}? They will become a member of this team's roster.`)) {
      return;
    }
    await assign(member.membershipId, selectedTeamId);
  }

  return (
    <li className="flex flex-col gap-1.5 border-b border-base-border pb-2.5 last:border-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between sm:gap-2">
      <span className="text-sm text-ink-secondary">{member.displayName}</span>
      {canManage && teams.length > 0 && (
        <div className="flex items-center gap-1.5">
          <select
            value={selectedTeamId}
            onChange={(e) => setSelectedTeamId(e.target.value)}
            disabled={assigning === member.membershipId}
            className="rounded-sm border border-base-border bg-base-raised px-2 py-1 text-xs text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          >
            {teams.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </select>
          <button
            onClick={handleAssign}
            disabled={assigning === member.membershipId || !selectedTeamId}
            className="flex items-center gap-1 rounded-sm bg-brand px-2 py-1 text-xs font-medium text-white hover:opacity-90 disabled:opacity-60"
          >
            <UserPlus size={12} />
            Assign to Team
          </button>
        </div>
      )}
      {error && <span className="text-xs text-signal-danger">{error}</span>}
    </li>
  );
}

function UnassignedSection({
  leagueId,
  members,
  teams,
  canManage,
}: {
  leagueId: string;
  members: RosterMember[];
  teams: TeamWithRoster[];
  canManage: boolean;
}) {
  if (members.length === 0) return null;

  return (
    <div className="panel p-5">
      <h3 className="font-display text-sm font-semibold text-ink-primary">Unassigned</h3>
      <p className="mt-1 text-xs text-ink-muted">
        League members not currently assigned to a team.
        {canManage && teams.length === 0 ? ' Add a team to this league before assigning them.' : ''}
      </p>
      <ul className="mt-3 space-y-1.5">
        {members.map((member) => (
          <UnassignedMemberRow key={member.membershipId} leagueId={leagueId} member={member} teams={teams} canManage={canManage} />
        ))}
      </ul>
    </div>
  );
}

export function LeagueRostersPanel({
  leagueId,
  teams,
  unassigned,
  claims,
  canManage,
}: {
  leagueId: string;
  teams: TeamWithRoster[];
  unassigned: RosterMember[];
  claims: TeamClaim[];
  canManage: boolean;
}) {
  if (teams.length === 0 && unassigned.length === 0) {
    return <EmptyState icon={Shield} title="No teams or members yet" />;
  }

  const claimsByTeamId = new Map<string, TeamClaim[]>();
  for (const claim of claims) {
    const list = claimsByTeamId.get(claim.teamId) ?? [];
    list.push(claim);
    claimsByTeamId.set(claim.teamId, list);
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {teams.map((team) => (
          <TeamCard
            key={team.id}
            leagueId={leagueId}
            team={team}
            claims={claimsByTeamId.get(team.id) ?? []}
            canManage={canManage}
          />
        ))}
      </div>
      <UnassignedSection leagueId={leagueId} members={unassigned} teams={teams} canManage={canManage} />
    </div>
  );
}
