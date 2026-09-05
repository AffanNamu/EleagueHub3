'use client';

import { useEffect } from 'react';
import { X } from 'lucide-react';

export function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-md rounded-lg border border-base-border bg-base-panel shadow-xl">
        <div className="flex items-center justify-between border-b border-base-border px-5 py-3.5">
          <h2 className="font-display text-sm font-semibold text-ink-primary">{title}</h2>
          <button
            onClick={onClose}
            className="rounded-sm p-1 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
            aria-label="Close"
          >
            <X size={16} />
          </button>
        </div>
        <div className="px-5 py-4">{children}</div>
      </div>
    </div>
  );
}
