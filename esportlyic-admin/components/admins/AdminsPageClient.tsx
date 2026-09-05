'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Plus, ShieldCheck, Trash2, Pencil } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import type { AdminUserRecord } from '@/types/adminRole';
import type { AdminRole } from '@/types/adminRole';

function AdminFormModal({
  mode,
  existing,
  roles,
  onClose,
  onSaved,
}: {
  mode: 'add' | 'edit';
  existing: AdminUserRecord | null;
  roles: AdminRole[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [email, setEmail] = useState('');
  const [roleIds, setRoleIds] = useState<string[]>(existing?.roleIds ?? []);
  const [grantLegacy, setGrantLegacy] = useState(existing?.isLegacyFullAccess ?? false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggleRole(id: string) {
    setRoleIds((prev) => (prev.includes(id) ? prev.filter((r) => r !== id) : [...prev, id]));
  }

  async function handleSubmit() {
    setSubmitting(true);
    setError(null);

    const url = mode === 'add' ? '/api/admin/admins' : `/api/admin/admins/${existing!.uid}`;
    const method = mode === 'add' ? 'POST' : 'PATCH';
    const body = mode === 'add' ? { email, roleIds, grantLegacyPricingAdmin: grantLegacy } : { roleIds, grantLegacyPricingAdmin: grantLegacy };

    try {
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        const responseBody = await response.json().catch(() => ({}));
        setError(responseBody.error ?? 'Something went wrong.');
        setSubmitting(false);
        return;
      }

      onSaved();
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
    }
  }

  return (
    <Modal title={mode === 'add' ? 'Add Admin' : `Edit Access — ${existing?.email || existing?.uid}`} onClose={onClose}>
      <div className="space-y-4">
        {error && (
          <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
            {error}
          </div>
        )}

        {mode === 'add' && (
          <div>
            <label className="mb-1.5 block text-sm text-ink-secondary">Email</label>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="The person must already have an account in the app."
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            />
          </div>
        )}

        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Roles</label>
          {roles.length === 0 ? (
            <p className="text-sm text-ink-secondary">
              No roles exist yet — create one on the Roles & Permissions page first.
            </p>
          ) : (
            <div className="space-y-1.5">
              {roles.map((role) => (
                <label key={role.roleId} className="flex cursor-pointer items-center gap-2.5 rounded-sm px-2 py-1.5 hover:bg-base-raised">
                  <input
                    type="checkbox"
                    checked={roleIds.includes(role.roleId)}
                    onChange={() => toggleRole(role.roleId)}
                    className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
                  />
                  <span className="text-sm text-ink-primary">{role.name}</span>
                </label>
              ))}
            </div>
          )}
        </div>

        <label className="flex cursor-pointer items-start gap-2.5 rounded-sm bg-base-raised px-3 py-2.5">
          <input
            type="checkbox"
            checked={grantLegacy}
            onChange={(event) => setGrantLegacy(event.target.checked)}
            className="mt-0.5 h-4 w-4 rounded-sm border-base-border bg-base text-signal-warning focus:ring-signal-warning"
          />
          <div>
            <p className="text-sm text-ink-primary">Also grant mobile app pricing-admin access</p>
            <p className="text-xs text-ink-secondary">
              This gives full, unrestricted access on the mobile app (pricing, badge grants, payments) —
              much broader than the web roles above. Only enable this if the person genuinely needs
              mobile-side admin tools.
            </p>
          </div>
        </label>

        <div className="flex justify-end gap-2 border-t border-base-border pt-3">
          <button onClick={onClose} className="rounded-sm px-3 py-1.5 text-sm text-ink-secondary hover:bg-base-raised">
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={submitting || (mode === 'add' && !email.trim())}
            className="rounded-sm bg-brand px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
          >
            {submitting ? 'Saving…' : mode === 'add' ? 'Add Admin' : 'Save Changes'}
          </button>
        </div>
      </div>
    </Modal>
  );
}

export function AdminsPageClient({
  initialAdmins,
  roles,
}: {
  initialAdmins: AdminUserRecord[];
  roles: AdminRole[];
}) {
  const router = useRouter();
  const [modalState, setModalState] = useState<'closed' | 'add' | AdminUserRecord>('closed');
  const [actionError, setActionError] = useState<string | null>(null);

  function refresh() {
    setModalState('closed');
    router.refresh();
  }

  async function handleRemove(admin: AdminUserRecord) {
    if (admin.isSuperAdmin) return;
    if (!confirm(`Remove admin access for ${admin.email || admin.uid}?`)) return;

    setActionError(null);
    const response = await fetch(`/api/admin/admins/${admin.uid}`, { method: 'DELETE' });

    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setActionError(body.error ?? 'Could not remove this admin.');
      return;
    }

    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Admins</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Everyone with access to this workspace, and what job each of them holds.
          </p>
        </div>
        <button
          onClick={() => setModalState('add')}
          className="flex items-center gap-2 rounded-sm bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-soft"
        >
          <Plus size={15} /> Add Admin
        </button>
      </div>

      {actionError && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {actionError}
        </div>
      )}

      {initialAdmins.length === 0 ? (
        <EmptyState icon={ShieldCheck} title="No admins yet" />
      ) : (
        <div className="panel overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                <th className="px-4 py-3 font-medium">Admin</th>
                <th className="px-4 py-3 font-medium">Access</th>
                <th className="px-4 py-3 font-medium" />
              </tr>
            </thead>
            <tbody>
              {initialAdmins.map((admin) => (
                <tr key={admin.uid} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                  <td className="px-4 py-3">
                    <p className="font-medium text-ink-primary">{admin.email || admin.uid}</p>
                    {admin.email && <p className="text-xs text-ink-muted">{admin.uid}</p>}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1.5">
                      {admin.isSuperAdmin && <Badge tone="brand">Super Admin</Badge>}
                      {!admin.isSuperAdmin && admin.isLegacyFullAccess && (
                        <Badge tone="warning">Legacy Full Access</Badge>
                      )}
                      {!admin.isSuperAdmin &&
                        admin.roleNames.map((name) => (
                          <Badge key={name} tone="info">
                            {name}
                          </Badge>
                        ))}
                      {!admin.isSuperAdmin && !admin.isLegacyFullAccess && admin.roleNames.length === 0 && (
                        <span className="text-xs text-ink-muted">No roles assigned</span>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    {!admin.isSuperAdmin && (
                      <div className="flex justify-end gap-1">
                        <button
                          onClick={() => setModalState(admin)}
                          className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                          aria-label="Edit access"
                        >
                          <Pencil size={14} />
                        </button>
                        <button
                          onClick={() => handleRemove(admin)}
                          className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-signal-danger"
                          aria-label="Remove admin"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {modalState !== 'closed' && (
        <AdminFormModal
          mode={modalState === 'add' ? 'add' : 'edit'}
          existing={modalState === 'add' ? null : modalState}
          roles={roles}
          onClose={() => setModalState('closed')}
          onSaved={refresh}
        />
      )}
    </div>
  );
}
