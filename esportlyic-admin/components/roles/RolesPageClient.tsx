'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Plus, Pencil, Trash2, ShieldCheck } from 'lucide-react';
import { RoleFormModal } from '@/components/roles/RoleFormModal';
import { EmptyState } from '@/components/ui/EmptyState';
import type { AdminRole } from '@/types/adminRole';

export function RolesPageClient({ initialRoles }: { initialRoles: AdminRole[] }) {
  const router = useRouter();
  const [modalState, setModalState] = useState<'closed' | 'create' | AdminRole>('closed');
  const [deleteError, setDeleteError] = useState<string | null>(null);

  function refresh() {
    setModalState('closed');
    router.refresh();
  }

  async function handleDelete(role: AdminRole) {
    if (!confirm(`Delete the role "${role.name}"? This cannot be undone.`)) return;

    setDeleteError(null);
    const response = await fetch(`/api/admin/roles/${role.roleId}`, { method: 'DELETE' });

    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setDeleteError(body.error ?? 'Could not delete this role.');
      return;
    }

    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Roles & Permissions</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Define named bundles of permissions, then assign them to admins on the Admins page.
          </p>
        </div>
        <button
          onClick={() => setModalState('create')}
          className="flex items-center gap-2 rounded-sm bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-soft"
        >
          <Plus size={15} /> Create Role
        </button>
      </div>

      {deleteError && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {deleteError}
        </div>
      )}

      {initialRoles.length === 0 ? (
        <EmptyState
          icon={ShieldCheck}
          title="No roles created yet"
          description='Create your first role — for example, "Social Admin" with report review and chat request permissions.'
        />
      ) : (
        <div className="panel overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                <th className="px-4 py-3 font-medium">Role</th>
                <th className="px-4 py-3 font-medium">Permissions</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody>
              {initialRoles.map((role) => (
                <tr key={role.roleId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                  <td className="px-4 py-3">
                    <p className="font-medium text-ink-primary">{role.name}</p>
                    <p className="text-xs text-ink-secondary">{role.description}</p>
                  </td>
                  <td className="px-4 py-3 text-ink-secondary">
                    {role.permissions.length} permission{role.permissions.length === 1 ? '' : 's'}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex justify-end gap-1">
                      <button
                        onClick={() => setModalState(role)}
                        className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                        aria-label="Edit role"
                      >
                        <Pencil size={14} />
                      </button>
                      <button
                        onClick={() => handleDelete(role)}
                        className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger"
                        aria-label="Delete role"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {modalState !== 'closed' && (
        <RoleFormModal
          existingRole={modalState === 'create' ? null : modalState}
          onClose={() => setModalState('closed')}
          onSaved={refresh}
        />
      )}
    </div>
  );
}
