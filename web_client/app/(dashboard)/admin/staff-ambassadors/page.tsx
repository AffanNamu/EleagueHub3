'use client';

// Mirrors lib/features/admin/staff_ambassador_admin_screen.dart — grants/
// revokes the purple Staff/Ambassador badge (verification.staffVerified)
// by Firebase UID, with a roster of current holders. Dart gates this
// screen on a hardcoded uid ('a0JDUelQW3TEyoXTm4ESuGi7ndq1') that does NOT
// match what firestore.rules' isBadgeAdminWrite/isPricingAdmin() actually
// requires (the uid used everywhere else on web, e.g.
// verification-requests's isPricingAdminUid) — gating on the real,
// authoritative uid here instead, same fix as the earlier
// global-chat-requests uid mismatch.

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { isPricingAdminUid } from '@/lib/admin/appAdminsRepository';
import { listStaffUserIds, grantStaffBadgeWeb, revokeStaffBadgeWeb } from '@/lib/verification/badgeRepository';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, RefreshCw, Shield, ShieldMinus, ClipboardPaste, ShieldAlert, Info } from 'lucide-react';

function looksLikeFirebaseUid(s: string): boolean {
  return s.trim().length > 20;
}

interface RosterEntry {
  userId: string;
  displayName: string;
  shareId: string;
}

export default function StaffAmbassadorAdminScreen() {
  const router = useRouter();
  const [authUid, setAuthUid] = useState<string | null | undefined>(undefined);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);

  const [uidInput, setUidInput] = useState('');
  const [granting, setGranting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [loadingRoster, setLoadingRoster] = useState(true);
  const [rosterError, setRosterError] = useState<string | null>(null);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  useEffect(() => {
    if (authUid === undefined) return;
    let cancelled = false;
    isPricingAdminUid(authUid).then((ok) => {
      if (!cancelled) setIsAdmin(ok);
    });
    return () => {
      cancelled = true;
    };
  }, [authUid]);

  useEffect(() => {
    if (isAdmin) loadRoster();
  }, [isAdmin]);

  async function loadRoster() {
    setLoadingRoster(true);
    setRosterError(null);
    try {
      const ids = await listStaffUserIds();
      const entries = await Promise.all(
        ids.map(async (userId): Promise<RosterEntry> => {
          const snap = await getDoc(doc(db, 'users', userId));
          const data = snap.data();
          const displayName = (data?.teamName || data?.displayName || userId) as string;
          const shareId = (data?.shareId || '') as string;
          return { userId, displayName, shareId };
        }),
      );
      setRoster(entries);
    } catch (e) {
      setRosterError(e instanceof Error ? e.message : 'Could not load roster.');
    } finally {
      setLoadingRoster(false);
    }
  }

  async function handlePaste() {
    try {
      const text = (await navigator.clipboard.readText()).trim();
      if (text) {
        setUidInput(text);
        setError(null);
      }
    } catch {
      // Clipboard read denied — ignore, matches Dart's silent no-op here.
    }
  }

  async function handleGrant() {
    if (granting) return;
    const rawUid = uidInput.trim();

    if (!rawUid) {
      setError('Please enter a user UID.');
      return;
    }
    if (!looksLikeFirebaseUid(rawUid)) {
      setError("That doesn't look like a valid Firebase UID. Copy it exactly from the user's profile.");
      return;
    }
    if (authUid && rawUid === authUid) {
      setError('You are already an admin — no badge needed.');
      return;
    }

    setGranting(true);
    setError(null);
    try {
      const snap = await getDoc(doc(db, 'users', rawUid));
      if (!snap.exists()) {
        setError('No user found with that UID. Double-check it and try again.');
        return;
      }

      await grantStaffBadgeWeb(rawUid);
      setUidInput('');
      await loadRoster();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not grant badge.');
    } finally {
      setGranting(false);
    }
  }

  async function handleRevoke(userId: string) {
    if (!confirm('Revoke this user’s Staff / Ambassador badge? They will immediately lose the purple verification badge.')) return;
    try {
      await revokeStaffBadgeWeb(userId);
      await loadRoster();
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Could not revoke badge.');
    }
  }

  if (isAdmin === null) {
    return <div className="flex justify-center py-24"><Loader2 className="w-8 h-8 animate-spin text-[#BEF264]" /></div>;
  }

  if (isAdmin === false) {
    return (
      <div className="max-w-2xl mx-auto text-center py-24">
        <ShieldAlert className="w-10 h-10 text-red-500 mx-auto mb-3" />
        <p className="text-red-500 font-black">You don&apos;t have access to this screen.</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6 pb-20 px-4 mt-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-2xl font-black text-white flex-1">Staff / Ambassadors</h1>
        <button onClick={loadRoster} disabled={loadingRoster} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-gray-300 hover:text-white disabled:opacity-50">
          <RefreshCw className={`w-4 h-4 ${loadingRoster ? 'animate-spin' : ''}`} />
        </button>
      </div>

      <Glass className="p-5 bg-[#0B1221] border-[#1E293B] rounded-2xl space-y-4">
        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-full bg-[#7C3AED]/15 border border-[#7C3AED]/30 flex items-center justify-center shrink-0">
            <Shield className="w-5 h-5 text-[#7C3AED]" />
          </div>
          <p className="font-black text-white">Grant Staff / Ambassador Badge</p>
        </div>
        <p className="text-xs text-gray-400 font-semibold leading-relaxed">
          Enter the Firebase UID of the user you want to make a staff member or ambassador. They&apos;ll get the purple shield badge shown next to their name app-wide.
        </p>

        <div className="relative">
          <input
            value={uidInput}
            onChange={(e) => {
              setUidInput(e.target.value);
              if (error) setError(null);
            }}
            onKeyDown={(e) => e.key === 'Enter' && handleGrant()}
            disabled={granting}
            placeholder="e.g. a0JDUelQW3TEyoXTm4ESuGi7ndq1"
            className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl pl-4 pr-11 py-3 text-white text-sm outline-none focus:border-[#7C3AED] disabled:opacity-60"
          />
          <button
            onClick={handlePaste}
            disabled={granting}
            title="Paste"
            className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 text-gray-500 hover:text-white disabled:opacity-50"
          >
            <ClipboardPaste className="w-4 h-4" />
          </button>
        </div>

        {error && (
          <div className="bg-red-500/10 border border-red-500/25 rounded-xl p-3">
            <p className="text-xs font-bold text-red-400">{error}</p>
          </div>
        )}

        <button
          onClick={handleGrant}
          disabled={granting}
          className="w-full py-3.5 rounded-xl bg-[#7C3AED] text-white font-black flex items-center justify-center gap-2 disabled:opacity-50 hover:brightness-110 transition-all"
        >
          {granting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Shield className="w-4 h-4" />}
          {granting ? 'Granting...' : 'Grant Badge'}
        </button>
      </Glass>

      <div>
        <p className="text-lg font-black text-white mb-3 px-1">Current Staff / Ambassadors</p>

        {loadingRoster ? (
          <div className="flex justify-center py-10"><Loader2 className="w-6 h-6 animate-spin text-[#BEF264]" /></div>
        ) : rosterError ? (
          <Glass className="p-4 bg-[#0B1221] border-[#1E293B] rounded-2xl">
            <p className="text-sm font-bold text-red-500">{rosterError}</p>
          </Glass>
        ) : roster.length === 0 ? (
          <Glass className="p-4 bg-[#0B1221] border-[#1E293B] rounded-2xl flex items-center gap-3">
            <Info className="w-5 h-5 text-gray-500 shrink-0" />
            <p className="text-sm font-semibold text-gray-400">No staff or ambassadors yet.</p>
          </Glass>
        ) : (
          <div className="space-y-2.5">
            {roster.map((entry) => (
              <Glass key={entry.userId} className="p-3.5 bg-[#0B1221] border-[#1E293B] rounded-2xl flex items-center gap-3">
                <div className="w-9 h-9 rounded-full bg-[#7C3AED]/15 flex items-center justify-center shrink-0">
                  <Shield className="w-4.5 h-4.5 text-[#7C3AED]" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-black text-white text-sm truncate">{entry.displayName}</p>
                  {entry.shareId && <p className="text-xs font-semibold text-gray-500">{entry.shareId}</p>}
                </div>
                <button onClick={() => handleRevoke(entry.userId)} title="Revoke" className="p-2 text-gray-500 hover:text-red-500">
                  <ShieldMinus className="w-4.5 h-4.5" />
                </button>
              </Glass>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
