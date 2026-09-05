'use client';

import { permissionsByCategory } from '@/lib/permissions/permissionRegistry';

export function PermissionMatrix({
  selected,
  onChange,
}: {
  selected: string[];
  onChange: (ids: string[]) => void;
}) {
  const categories = permissionsByCategory();
  const selectedSet = new Set(selected);

  function toggle(id: string) {
    const next = new Set(selectedSet);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange(Array.from(next));
  }

  return (
    <div className="space-y-4">
      {Array.from(categories.entries()).map(([category, permissions]) => (
        <div key={category}>
          <p className="mb-2 text-xs font-medium text-ink-muted">{category}</p>
          <div className="space-y-1.5">
            {permissions.map((permission) => (
              <label
                key={permission.id}
                className="flex cursor-pointer items-start gap-2.5 rounded-sm px-2 py-1.5 hover:bg-base-raised"
              >
                <input
                  type="checkbox"
                  checked={selectedSet.has(permission.id)}
                  onChange={() => toggle(permission.id)}
                  className="mt-0.5 h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand"
                />
                <div>
                  <p className="text-sm text-ink-primary">{permission.label}</p>
                  <p className="text-xs text-ink-secondary">{permission.description}</p>
                </div>
              </label>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
