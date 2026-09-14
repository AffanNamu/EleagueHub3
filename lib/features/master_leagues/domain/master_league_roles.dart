///domain/master_league_roles
///
/// Shared role + capability registry for Master League workspace staff.
///
/// Storage contract: a Master League doc's `roles` field is
/// `Map<uid, String>` (see [MasterLeague.roles]). The owner is inferred
/// from `ownerId` and is never itself a value in that map's write path
/// (it's back-filled read-side for convenience — see
/// `MasterLeague._readRoles`). Only [MasterLeagueStaffRole.storageValue]
/// strings are ever written to `roles`; `competitionManager` intentionally
/// keeps the pre-existing `'admin'` storage string so already-assigned
/// staff are not silently reinterpreted or require a migration.
enum MasterLeagueStaffRole {
  /// Full control, implied by `ownerId` — never stored in the `roles` map
  /// and never assignable/removable through the staff-management APIs.
  owner(
    storageValue: 'owner',
    displayName: 'Owner',
    description: 'Full control of the workspace, including staff.',
  ),

  /// Broad day-to-day operational control: create/manage competitions and
  /// their results. Keeps the legacy `'admin'` storage value used by
  /// existing staff records and the current add-staff flow.
  competitionManager(
    storageValue: 'admin',
    displayName: 'Competition Manager',
    description:
        'Can create and manage competitions, and enter/edit results.',
  ),

  /// Narrow delegation for entering/editing match results without wider
  /// competition-management or moderation access.
  resultManager(
    storageValue: 'result_manager',
    displayName: 'Result Manager',
    description: 'Can enter and edit match results only.',
  ),

  /// Community moderation: organizer discipline + organizer chat.
  moderator(
    storageValue: 'moderator',
    displayName: 'Moderator',
    description:
        'Can apply organizer discipline and moderate organizer chat.',
  );

  const MasterLeagueStaffRole({
    required this.storageValue,
    required this.displayName,
    required this.description,
  });

  final String storageValue;
  final String displayName;
  final String description;

  /// Roles assignable through the staff-management UI/APIs. [owner] is
  /// deliberately excluded — ownership never transfers through staff CRUD.
  static const List<MasterLeagueStaffRole> assignable = [
    competitionManager,
    resultManager,
    moderator,
  ];

  static MasterLeagueStaffRole? fromStorageValue(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final role in values) {
      if (role.storageValue == normalized) return role;
    }
    return null;
  }

  bool get isAssignable => this != owner;
}

/// A discrete, checkable Master League workspace permission.
enum MasterLeagueCapability {
  /// Add/remove staff and change their roles. Owner-only, always.
  manageStaff,

  /// Create, edit, and delete competitions inside the workspace.
  manageCompetitions,

  /// Enter/edit match results and manage knockout/bracket progression.
  manageResults,

  /// Apply/reverse organizer discipline actions (warnings, points,
  /// organizer-chat mute/ban) — the `disciplineActions` /
  /// `memberModeration` subcollections.
  moderateDiscipline,

  /// Pin/delete messages and mute/ban participants in organizer chat.
  moderateChat,

  /// Post/edit/delete workspace announcements.
  manageAnnouncements,

  /// View workspace analytics.
  viewAnalytics,
}

const Map<MasterLeagueStaffRole, Set<MasterLeagueCapability>>
    _roleCapabilities = {
  MasterLeagueStaffRole.owner: {
    MasterLeagueCapability.manageStaff,
    MasterLeagueCapability.manageCompetitions,
    MasterLeagueCapability.manageResults,
    MasterLeagueCapability.moderateDiscipline,
    MasterLeagueCapability.moderateChat,
    MasterLeagueCapability.manageAnnouncements,
    MasterLeagueCapability.viewAnalytics,
  },
  // Also granted moderateDiscipline/moderateChat: the organizer discipline
  // and organizer chat screens have always treated "admin" as a general
  // staff role with moderation access (see their own "owner, admins, or
  // moderators" copy) — narrowing that here would regress already-shipped
  // behavior, not just tidy the model.
  MasterLeagueStaffRole.competitionManager: {
    MasterLeagueCapability.manageCompetitions,
    MasterLeagueCapability.manageResults,
    MasterLeagueCapability.moderateDiscipline,
    MasterLeagueCapability.moderateChat,
    MasterLeagueCapability.manageAnnouncements,
    MasterLeagueCapability.viewAnalytics,
  },
  MasterLeagueStaffRole.resultManager: {
    MasterLeagueCapability.manageResults,
  },
  MasterLeagueStaffRole.moderator: {
    MasterLeagueCapability.moderateDiscipline,
    MasterLeagueCapability.moderateChat,
  },
};

extension MasterLeagueStaffRoleCapabilities on MasterLeagueStaffRole {
  Set<MasterLeagueCapability> get capabilities =>
      _roleCapabilities[this] ?? const <MasterLeagueCapability>{};

  bool can(MasterLeagueCapability capability) =>
      capabilities.contains(capability);
}

/// Resolves a uid's effective role within a workspace given its
/// `ownerId` and `roles` map, then answers capability questions.
///
/// This is the single source of truth both [OrganizerDisciplineScreen]
/// and [OrganizerChatScreen]-style access checks should route through —
/// no screen should re-derive admin/moderator sets from `roles` by hand.
class MasterLeagueAccess {
  const MasterLeagueAccess({
    required this.ownerId,
    required this.roles,
  });

  final String ownerId;
  final Map<String, String> roles;

  factory MasterLeagueAccess.fromMap(Map<String, dynamic> data) {
    final ownerId = (data['ownerId'] as String? ?? '').trim();
    final rawRoles = data['roles'];
    final roles = <String, String>{};
    if (rawRoles is Map) {
      for (final entry in rawRoles.entries) {
        final k = entry.key.toString().trim();
        final v = entry.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) roles[k] = v;
      }
    }
    return MasterLeagueAccess(ownerId: ownerId, roles: roles);
  }

  MasterLeagueStaffRole? roleOf(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return null;
    if (id == ownerId.trim() && id.isNotEmpty) {
      return MasterLeagueStaffRole.owner;
    }
    return MasterLeagueStaffRole.fromStorageValue(roles[id]);
  }

  bool canUid(String uid, MasterLeagueCapability capability) {
    final role = roleOf(uid);
    if (role == null) return false;
    return role.can(capability);
  }

  Set<String> uidsWithRole(MasterLeagueStaffRole role) {
    if (role == MasterLeagueStaffRole.owner) {
      final owner = ownerId.trim();
      return owner.isEmpty ? const <String>{} : {owner};
    }
    return roles.entries
        .where((e) => e.value.trim().toLowerCase() == role.storageValue)
        .map((e) => e.key)
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> uidsWithCapability(MasterLeagueCapability capability) {
    final out = <String>{};
    for (final role in MasterLeagueStaffRole.values) {
      if (role.can(capability)) out.addAll(uidsWithRole(role));
    }
    return out;
  }
}
