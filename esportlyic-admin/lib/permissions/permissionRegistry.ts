// lib/permissions/permissionRegistry.ts

export interface PermissionDefinition {
  id: string;
  label: string;
  description: string;
  category: string;
  superAdminOnly?: boolean;
}

export const PERMISSIONS: PermissionDefinition[] = [
  // User Management
  { id: 'users.view', label: 'View Users', description: 'View user profiles and account details.', category: 'User Management' },
  { id: 'users.moderate', label: 'Moderate Users', description: 'Mute or ban a user from chat, and manage Global Chat moderator status.', category: 'User Management' },
  { id: 'admins.manage', label: 'Manage Admins', description: 'Add, remove, or change which admins have access and what roles they hold.', category: 'User Management', superAdminOnly: true },
  { id: 'roles.manage', label: 'Manage Roles', description: 'Create, edit, or delete admin roles and their permissions.', category: 'User Management', superAdminOnly: true },
  { id: 'verification.view', label: 'View Verification Requests', description: 'View organizer verification submissions.', category: 'User Management' },
  { id: 'verification.review', label: 'Review Verification Requests', description: 'Approve, reject, or request more information on organizer verification submissions.', category: 'User Management' },

  // Platform Management
  { id: 'organizers.view', label: 'View Organizers', description: 'View organizer workspace details.', category: 'Platform Management' },
  { id: 'organizers.manage', label: 'Manage Organizers', description: 'Edit organizer workspace details.', category: 'Platform Management' },
  { id: 'leagues.view', label: 'View Leagues', description: 'View league details.', category: 'Platform Management' },
  { id: 'leagues.manage', label: 'Manage Leagues', description: 'Edit or moderate league details.', category: 'Platform Management' },

  // Content & Engagement
  { id: 'content.view', label: 'View Content', description: 'View public posts and comments.', category: 'Content & Engagement' },
  { id: 'content.moderate', label: 'Moderate Content', description: 'Remove posts and comments that violate platform rules.', category: 'Content & Engagement' },

  // Moderation
  { id: 'reports.view', label: 'View Reports', description: 'View user-submitted reports.', category: 'Moderation' },
  { id: 'reports.review', label: 'Review Reports', description: 'Mark reports as reviewed or dismissed.', category: 'Moderation' },
  { id: 'global_chat_requests.view', label: 'View Global Chat Requests', description: 'View requests for Global Chat access.', category: 'Moderation' },
  { id: 'global_chat_requests.review', label: 'Review Global Chat Requests', description: 'Approve or reject requests for Global Chat access.', category: 'Moderation' },

  // Monetization
  { id: 'payments.view', label: 'View Payments', description: 'View payment history and revenue summaries.', category: 'Monetization' },
  { id: 'payments.override_entitlement', label: 'Override Entitlements', description: 'Manually grant or revoke a Pro/Elite plan — bypasses payment verification entirely. Reserved for the Super Admin.', category: 'Monetization', superAdminOnly: true },
  { id: 'pricing.view', label: 'View Pricing', description: 'View the platform pricing configuration.', category: 'Monetization' },
  { id: 'pricing.edit', label: 'Edit Pricing', description: 'Edit the platform pricing configuration.', category: 'Monetization' },

  // System
  { id: 'analytics.view', label: 'View Analytics', description: 'View platform-wide analytics and dashboards.', category: 'System' },
  { id: 'audit_logs.view', label: 'View Audit Logs', description: 'View the admin action audit trail.', category: 'System' },
  { id: 'settings.manage', label: 'Manage Settings', description: 'Edit platform-wide system settings.', category: 'System' },
];

export function getAssignablePermissions(): PermissionDefinition[] {
  return PERMISSIONS.filter((p) => !p.superAdminOnly);
}

export function isAssignablePermissionId(id: string): boolean {
  return PERMISSIONS.some((p) => p.id === id && !p.superAdminOnly);
}

export function permissionsByCategory(): Map<string, PermissionDefinition[]> {
  const map = new Map<string, PermissionDefinition[]>();
  for (const permission of getAssignablePermissions()) {
    const list = map.get(permission.category) ?? [];
    list.push(permission);
    map.set(permission.category, list);
  }
  return map;
}
