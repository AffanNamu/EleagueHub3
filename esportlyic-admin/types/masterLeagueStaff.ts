// types/masterLeagueStaff.ts
//
// Admin-facing view of a master_leagues/{id} doc's staff (owner + roles
// map + staffScopes map) and its staffAuditLog subcollection. Mirrors
// the storage contract in lib/features/master_leagues/domain/master_league_roles.dart
// (mobile) and web_client/lib/masterLeagues/roles.ts (web) — this is a
// third, read/moderate-only port of that same contract for the admin panel.

export type MasterLeagueStaffRoleValue = 'owner' | 'admin' | 'result_manager' | 'moderator';

export interface MasterLeagueStaffMember {
  uid: string;
  /** Storage value: 'owner' | 'admin' (Competition Manager) | 'result_manager' | 'moderator'. */
  role: string;
  roleLabel: string;
  isOwner: boolean;
  /** League IDs this staff member is scoped to. Empty = unrestricted (all competitions). */
  scopeLeagueIds: string[];
  displayName: string;
  photoUrl: string;
}

export interface MasterLeagueStaffAuditEntry {
  id: string;
  action: string;
  performedBy: string;
  performedByName: string;
  targetUserId: string;
  targetUserName: string;
  targetRole: string;
  details: string;
  performedAtMs: number;
}
