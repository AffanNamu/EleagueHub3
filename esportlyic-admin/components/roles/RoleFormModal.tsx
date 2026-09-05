'use client';

import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { PermissionMatrix } from '@/components/roles/PermissionMatrix';
import type { AdminRole } from '@/types/adminRole';

export function RoleFormModal({
  existingRole,
  onClose,
  onSaved,
}: {
  existingRole: AdminRole | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(existingRole?.name ?? '');
  const [description, setDescription] = useState(existingRole?.description ?? '');
  const [permissions, setPermissions] = useState<string[]>(existingRole?.permissions ?? []);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    setSubmitting(true);
    setError(null);

    const url = existingRole ? `/api/admin/roles/${existingRole.roleId}` : '/api/admin/roles';
    const method = existingRole ? 'PATCH' : 'POST';

    try {
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, description, permissions }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Something went wrong.');
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
    <Modal title={existingRole ? 'Edit Role' : 'Create Role'} onClose={onClose}>
      <div className="max-h-[70vh] space-y-4 overflow-y-auto">
        {error && (
          <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
            {error}
          </div>
        )}

        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Role Name</label>
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="e.g. Social Admin"
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>

        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Description</label>
          <input
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            placeholder="e.g. Handles chat moderation and user reports"
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm text-ink-secondary">Permissions</label>
          <PermissionMatrix selected={permissions} onChange={setPermissions} />
        </div>

        <div className="flex justify-end gap-2 border-t border-base-border pt-3">
          <button onClick={onClose} className="rounded-sm px-3 py-1.5 text-sm text-ink-secondary hover:bg-base-raised">
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={submitting || !name.trim() || permissions.length === 0}
            className="rounded-sm bg-brand px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
          >
            {submitting ? 'Saving…' : existingRole ? 'Save Changes' : 'Create Role'}
          </button>
        </div>
      </div>
    </Modal>
  );
}
