'use client';

import { useEffect, useRef, useState } from 'react';
import { X, Check, Loader2 } from 'lucide-react';
import {
  isUsernameAvailable,
  updateUsername,
  UsernameUnavailableError,
} from '@/lib/services/userProfileRepository';
import {
  isValidUsernameFormat,
  isReservedUsername,
  USERNAME_MIN_LENGTH,
  USERNAME_MAX_LENGTH,
} from '@/lib/username';

type CheckState = 'idle' | 'checking' | 'available' | 'taken' | 'invalid' | 'error';

interface UsernameEditModalProps {
  authUid: string;
  /** Current usernameLower, may be '' if not yet assigned. */
  current: string;
  onClose: () => void;
  onSaved: (newUsernameLower: string) => void;
}

export function UsernameEditModal({ authUid, current, onClose, onSaved }: UsernameEditModalProps) {
  const [value, setValue] = useState(current);
  const [checkState, setCheckState] = useState<CheckState>('idle');
  const [errorText, setErrorText] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  function handleChange(raw: string) {
    setValue(raw);
    const candidate = raw.trim().toLowerCase();

    if (debounceRef.current) clearTimeout(debounceRef.current);

    if (candidate === current.trim().toLowerCase()) {
      setCheckState('idle');
      setErrorText(null);
      return;
    }

    if (!isValidUsernameFormat(candidate)) {
      setCheckState('invalid');
      setErrorText(
        `${USERNAME_MIN_LENGTH}-${USERNAME_MAX_LENGTH} characters: lowercase letters, numbers, and _ only.`,
      );
      return;
    }

    if (isReservedUsername(candidate)) {
      setCheckState('taken');
      setErrorText('That username is reserved.');
      return;
    }

    setCheckState('checking');
    setErrorText(null);

    debounceRef.current = setTimeout(async () => {
      try {
        const available = await isUsernameAvailable(candidate, authUid);
        setCheckState(available ? 'available' : 'taken');
        setErrorText(available ? null : 'Username already taken.');
      } catch (err) {
        setCheckState('error');
        setErrorText(err instanceof Error ? err.message : 'Could not check availability.');
      }
    }, 450);
  }

  async function handleSave() {
    const candidate = value.trim().toLowerCase();
    if (!candidate || candidate === current.trim().toLowerCase()) {
      onClose();
      return;
    }

    setSaving(true);
    try {
      await updateUsername(authUid, candidate, current.trim().toLowerCase());
      onSaved(candidate);
    } catch (err) {
      setSaving(false);
      setCheckState('taken');
      setErrorText(
        err instanceof UsernameUnavailableError
          ? err.message
          : err instanceof Error
            ? err.message
            : 'Could not save username.',
      );
    }
  }

  const canSave = !saving && (checkState === 'available' || checkState === 'idle');

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div className="w-full max-w-sm bg-[#0B1221] border border-[#1E293B] rounded-2xl p-5 relative shadow-2xl">
        <button
          onClick={onClose}
          disabled={saving}
          className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-lg font-black text-white mb-4">Edit Username</h3>

        <div className="flex items-center gap-2 mb-2">
          <span className="text-slate-500 font-bold">@</span>
          <input
            autoFocus
            value={value}
            disabled={saving}
            onChange={(e) => handleChange(e.target.value)}
            placeholder="yourusername"
            className="flex-1 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40 disabled:opacity-60"
          />
        </div>

        <div className="min-h-[20px] mb-4">
          {checkState === 'checking' && (
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-400">
              <Loader2 className="w-3 h-3 animate-spin" /> Checking availability…
            </div>
          )}
          {checkState === 'available' && (
            <div className="flex items-center gap-2 text-xs font-bold text-emerald-400">
              <Check className="w-3 h-3" /> Username available
            </div>
          )}
          {(checkState === 'taken' || checkState === 'invalid' || checkState === 'error') &&
            errorText && <div className="text-xs font-bold text-red-400">{errorText}</div>}
        </div>

        <div className="flex gap-2">
          <button
            onClick={onClose}
            disabled={saving}
            className="flex-1 py-2.5 rounded-xl bg-white/5 hover:bg-white/10 text-white text-sm font-black transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={!canSave}
            className="flex-1 py-2.5 rounded-xl bg-brand-lime text-slate-900 text-sm font-black hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
