// lib/masterLeagues/roles.ts
//
// Shared role + capability registry for Master League workspace staff.
// Mirrors lib/features/master_leagues/domain/master_league_roles.dart —
// keep both in sync by hand (same pattern as leagueFormat.ts).
//
// Storage contract: a Master League doc's `roles` field is
// Record<uid, string>. The owner is inferred from `ownerId` and is never
// itself written into that map. `competitionManager` intentionally keeps
// the pre-existing `'admin'` storage string so already-assigned staff are
// not silently reinterpreted or require a migration.

export type MasterLeagueStaffRoleId =
  | 'owner'
  | 'admin' // storage value for competitionManager
  | 'result_manager'
  | 'moderator';

export interface MasterLeagueStaffRoleDef {
  id: MasterLeagueStaffRoleId;
  displayName: string;
  description: string;
  /** true for every role except owner, which is never assignable/removable through staff CRUD. */
  isAssignable: boolean;
}

export const MASTER_LEAGUE_STAFF_ROLES: Record<MasterLeagueStaffRoleId, MasterLeagueStaffRoleDef> = {
  owner: {
    id: 'owner',
    displayName: 'Owner',
    description: 'Full control of the workspace, including staff.',
    isAssignable: false,
  },
  admin: {
    id: 'admin',
    displayName: 'Competition Manager',
    description: 'Can create and manage competitions, and enter/edit results.',
    isAssignable: true,
  },
  result_manager: {
    id: 'result_manager',
    displayName: 'Result Manager',
    description: 'Can enter and edit match results only.',
    isAssignable: true,
  },
  moderator: {
    id: 'moderator',
    displayName: 'Moderator',
    description: 'Can apply organizer discipline and moderate organizer chat.',
    isAssignable: true,
  },
};

export const ASSIGNABLE_STAFF_ROLES: MasterLeagueStaffRoleId[] = ['admin', 'result_manager', 'moderator'];

export function staffRoleFromStorageValue(raw: unknown): MasterLeagueStaffRoleId | null {
  const s = String(raw ?? '').trim().toLowerCase();
  if (s === 'owner' || s === 'admin' || s === 'result_manager' || s === 'moderator') return s;
  return null;
}

export type MasterLeagueCapability =
  | 'manageStaff'
  | 'manageCompetitions'
  | 'manageResults'
  | 'moderateDiscipline'
  | 'moderateChat'
  | 'manageAnnouncements'
  | 'viewAnalytics';

const ROLE_CAPABILITIES: Record<MasterLeagueStaffRoleId, MasterLeagueCapability[]> = {
  owner: [
    'manageStaff',
    'manageCompetitions',
    'manageResults',
    'moderateDiscipline',
    'moderateChat',
    'manageAnnouncements',
    'viewAnalytics',
  ],
  // Also grants moderateDiscipline/moderateChat: the organizer discipline
  // and organizer chat screens have always treated "admin" as a general
  // staff role with moderation access (see their own "owner, admins, or
  // moderators" copy) — narrowing that here would regress already-shipped
  // behavior, not just tidy the model.
  admin: [
    'manageCompetitions',
    'manageResults',
    'moderateDiscipline',
    'moderateChat',
    'manageAnnouncements',
    'viewAnalytics',
  ],
  result_manager: ['manageResults'],
  moderator: ['moderateDiscipline', 'moderateChat'],
};

export function roleCapabilities(role: MasterLeagueStaffRoleId): MasterLeagueCapability[] {
  return ROLE_CAPABILITIES[role] ?? [];
}

export function roleCan(role: MasterLeagueStaffRoleId, capability: MasterLeagueCapability): boolean {
  return roleCapabilities(role).includes(capability);
}

/**
 * Resolves a uid's effective role within a workspace given its `ownerId`
 * and `roles` map, then answers capability questions. Every access check
 * (discipline, organizer chat moderation, staff UI, etc.) should route
 * through this instead of re-deriving admin/moderator sets by hand.
 */
export class MasterLeagueAccess {
  readonly ownerId: string;
  readonly roles: Record<string, string>;

  constructor(ownerId: string, roles: Record<string, string>) {
    this.ownerId = (ownerId ?? '').trim();
    this.roles = roles ?? {};
  }

  static fromData(data: Record<string, unknown>): MasterLeagueAccess {
    const ownerId = (data?.ownerId ?? '').toString().trim();
    const rawRoles = data?.roles;
    const roles: Record<string, string> = {};
    if (rawRoles && typeof rawRoles === 'object') {
      for (const [k, v] of Object.entries(rawRoles)) {
        const key = String(k).trim();
        const val = v == null ? '' : String(v).trim();
        if (key && val) roles[key] = val;
      }
    }
    return new MasterLeagueAccess(ownerId, roles);
  }

  roleOf(uid: string): MasterLeagueStaffRoleId | null {
    const id = (uid ?? '').trim();
    if (!id) return null;
    if (id === this.ownerId && id) return 'owner';
    return staffRoleFromStorageValue(this.roles[id]);
  }

  can(uid: string, capability: MasterLeagueCapability): boolean {
    const role = this.roleOf(uid);
    if (!role) return false;
    return roleCan(role, capability);
  }

  uidsWithRole(role: MasterLeagueStaffRoleId): Set<string> {
    if (role === 'owner') {
      return this.ownerId ? new Set([this.ownerId]) : new Set();
    }
    const out = new Set<string>();
    for (const [uid, r] of Object.entries(this.roles)) {
      if (r.trim().toLowerCase() === role && uid.trim()) out.add(uid.trim());
    }
    return out;
  }

  uidsWithCapability(capability: MasterLeagueCapability): Set<string> {
    const out = new Set<string>();
    (Object.keys(MASTER_LEAGUE_STAFF_ROLES) as MasterLeagueStaffRoleId[]).forEach((role) => {
      if (roleCan(role, capability)) {
        this.uidsWithRole(role).forEach((uid) => out.add(uid));
      }
    });
    return out;
  }
}
