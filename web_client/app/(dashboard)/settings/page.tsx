/*app/(dashboard)/Settings/page.tsx*/
'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { onAuthStateChanged, User as FirebaseUser } from 'firebase/auth';
import { FirebaseError } from 'firebase/app';
import { doc, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { SupabaseEdgeNotificationsService } from '@/lib/services/supabaseEdgeNotifications';
import { updateQuickMessagesCustom } from '@/lib/services/userProfileRepository';
import {
  QUICK_MESSAGE_MAX_CHARS,
  QUICK_MESSAGE_MAX_COUNT,
  validateCustomQuickMessage,
} from '@/lib/services/quickMessagePolicy';
import { useTheme } from '@/components/providers/ClientThemeProvider';
import { Glass } from '@/components/ui/Glass';
import {
  Loader2, User, UserX, ShieldAlert, LogOut, Bell, Moon, Sun,
  MessageSquare, AlertTriangle, X, Check, Circle, Plus, Trash2,
  ChevronUp, ChevronDown, Lock, SendHorizonal, ScrollText, ChevronRight,
} from 'lucide-react';

// Mirrors the reason list in lib/features/profile/presentation/delete_account_flow.dart
const FEEDBACK_REASONS = [
  "I don't understand how to use the app",
  'I have privacy concerns',
  'The app is too buggy or slow',
  'I found a better alternative',
  'I receive too many notifications',
  'Other',
];

const NOTIF_PREFS_KEY = 'eh_notification_prefs';

type DeleteStep = 'idle' | 'warning' | 'feedback' | 'deleting';

export default function SettingsScreen() {
  const router = useRouter();
  const { theme, toggleTheme } = useTheme();

  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [isPremium, setIsPremium] = useState(false);
  const [customQuick, setCustomQuick] = useState<string[]>([]);

  const [error, setError] = useState('');
  const [deleteStep, setDeleteStep] = useState<DeleteStep>('idle');
  const [selectedReasons, setSelectedReasons] = useState<Set<string>>(new Set());
  const [feedbackText, setFeedbackText] = useState('');

  // Notification prefs — local-device preferences only, matching mobile's
  // PrefsService (SharedPreferences-backed, never synced to Firestore).
  // Persisted to localStorage so they survive a reload instead of a plain
  // in-memory useState resetting every time, like before.
  const [prefs, setPrefs] = useState({ pushEnabled: true, marketing: false, matchReminders: true });
  const [prefsLoaded, setPrefsLoaded] = useState(false);

  const [quickInput, setQuickInput] = useState('');
  const [quickError, setQuickError] = useState('');
  const [savingQuick, setSavingQuick] = useState(false);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(NOTIF_PREFS_KEY);
      if (raw) setPrefs((p) => ({ ...p, ...JSON.parse(raw) }));
    } catch {}
    setPrefsLoaded(true);
  }, []);

  useEffect(() => {
    if (!prefsLoaded) return;
    try { localStorage.setItem(NOTIF_PREFS_KEY, JSON.stringify(prefs)); } catch {}
  }, [prefs, prefsLoaded]);

  const togglePref = (key: keyof typeof prefs) => setPrefs((p) => ({ ...p, [key]: !p[key] }));

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setUser(u));
    return () => unsub();
  }, []);

  useEffect(() => {
    if (!user?.uid) return;
    const unsub = onSnapshot(doc(db, 'users', user.uid), (snap) => {
      const data = snap.data();
      setIsPremium(data?.isPremium === true);
      setCustomQuick(Array.isArray(data?.quickMessagesCustom) ? data!.quickMessagesCustom : []);
    });
    return () => unsub();
  }, [user?.uid]);

  const handleSignOut = async () => {
    await auth.signOut();
    router.push('/login');
  };

  // ── Quick messages ─────────────────────────────────────────────────────

  const handleAddQuickMessage = async () => {
    if (!user || savingQuick) return;
    const result = validateCustomQuickMessage(quickInput);
    if (!result.ok) { setQuickError(result.error); return; }
    if (customQuick.length >= QUICK_MESSAGE_MAX_COUNT) {
      setQuickError(`Max ${QUICK_MESSAGE_MAX_COUNT} messages`);
      return;
    }
    if (customQuick.some((m) => m.toLowerCase() === result.value.toLowerCase())) {
      setQuickInput('');
      return;
    }
    setSavingQuick(true);
    setQuickError('');
    try {
      await updateQuickMessagesCustom(user.uid, [...customQuick, result.value]);
      setQuickInput('');
    } catch (err) {
      setQuickError(err instanceof Error ? err.message : 'Could not save message.');
    } finally {
      setSavingQuick(false);
    }
  };

  const handleDeleteQuickMessage = async (index: number) => {
    if (!user) return;
    const next = customQuick.filter((_, i) => i !== index);
    await updateQuickMessagesCustom(user.uid, next);
  };

  const handleMoveQuickMessage = async (index: number, dir: -1 | 1) => {
    if (!user) return;
    const target = index + dir;
    if (target < 0 || target >= customQuick.length) return;
    const next = [...customQuick];
    [next[index], next[target]] = [next[target], next[index]];
    await updateQuickMessagesCustom(user.uid, next);
  };

  // ── Delete account flow (warning → feedback → deletion) ──────────────────
  // Mirrors lib/features/profile/presentation/delete_account_flow.dart +
  // AccountDeletionService: the Supabase edge-function cleanup call is
  // treated as best-effort/non-fatal (a failed cleanup call must never
  // block a user from actually deleting their auth account), then the
  // Firebase Auth user is hard-deleted, then local state is cleared.

  const toggleReason = (reason: string) => {
    setSelectedReasons((prev) => {
      const next = new Set(prev);
      if (next.has(reason)) next.delete(reason); else next.add(reason);
      return next;
    });
  };

  const runDeletion = async (feedbackReason: string, feedbackTextValue: string) => {
    setDeleteStep('deleting');
    setError('');
    try {
      try {
        await SupabaseEdgeNotificationsService.triggerAccountDeletion({
          feedbackReason,
          feedbackText: feedbackTextValue || undefined,
        });
      } catch (cleanupErr) {
        // Non-fatal — the user must still be able to delete their auth
        // account even if server-side data cleanup failed (e.g. network).
        console.error('[Settings] account data cleanup failed (non-fatal):', cleanupErr);
      }

      try { localStorage.clear(); } catch {}

      if (auth.currentUser) await auth.currentUser.delete();
      router.push('/login');
    } catch (err) {
      if (err instanceof FirebaseError && err.code === 'auth/requires-recent-login') {
        setError('Please sign out, sign back in, and try again to verify your identity.');
      } else {
        setError(err instanceof Error ? err.message : 'Failed to delete account.');
      }
      setDeleteStep('idle');
    }
  };

  const handleSkipFeedback = () => runDeletion('Skipped', '');

  const handleSubmitFeedback = () => {
    const reason = selectedReasons.size === 0 ? 'No reason given' : Array.from(selectedReasons).join(', ');
    runDeletion(reason, feedbackText);
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
          <Circle className="w-6 h-6 text-brand-lime" strokeWidth={3} /> Account Settings
        </h1>
        <p className="text-gray-400 mt-1">Manage your application preferences and security.</p>
      </div>

      {error && (
        <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span className="text-sm">{error}</span>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Left Column */}
        <div className="space-y-6">
          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <User className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Account</h3>
            </div>
            <div className="flex items-center gap-3 p-3 bg-brand-surface rounded-xl border border-white/5">
              <div className="w-10 h-10 rounded-full bg-[#38BDF8]/10 border border-[#38BDF8]/20 flex items-center justify-center shrink-0">
                <User className="w-5 h-5 text-[#38BDF8]" />
              </div>
              <div className="min-w-0">
                <p className="text-sm font-bold text-white truncate">{user?.displayName || 'My Account'}</p>
                <p className="text-xs text-gray-500 truncate">{user?.email || ''}</p>
              </div>
            </div>
          </Glass>

          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <Moon className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Appearance</h3>
            </div>
            <div className="flex items-center justify-between p-3 bg-brand-surface rounded-xl border border-white/5">
              <span className="text-sm font-bold text-gray-200">Theme</span>
              <button
                onClick={toggleTheme}
                className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-white text-xs font-bold transition-colors"
              >
                {theme === 'dark' ? <Moon className="w-4 h-4" /> : <Sun className="w-4 h-4" />}
                {theme === 'dark' ? 'Dark' : 'Light'}
              </button>
            </div>
          </Glass>

          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <Bell className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Notifications</h3>
            </div>
            <div className="space-y-4">
              <ToggleRow label="Enable Push Notifications" checked={prefs.pushEnabled} onChange={() => togglePref('pushEnabled')} />
              <ToggleRow label="Match Reminders" checked={prefs.matchReminders} onChange={() => togglePref('matchReminders')} disabled={!prefs.pushEnabled} />
              <ToggleRow label="Marketing & Promos" checked={prefs.marketing} onChange={() => togglePref('marketing')} disabled={!prefs.pushEnabled} />
            </div>
          </Glass>

          <Glass className="p-6">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <MessageSquare className="w-5 h-5 text-[#38BDF8]" />
                <h3 className="font-bold text-white">Quick Messages</h3>
              </div>
              {isPremium && (
                <span className="text-[10px] font-black uppercase tracking-wider text-amber-400 bg-amber-400/10 border border-amber-400/20 px-2 py-1 rounded-full">Premium</span>
              )}
            </div>
            <p className="text-xs text-gray-500 mb-4">
              Defaults are included automatically. Premium users can add up to {QUICK_MESSAGE_MAX_COUNT} custom quick messages ({QUICK_MESSAGE_MAX_CHARS} chars max) for live chat.
            </p>

            {!isPremium ? (
              <div className="flex items-center gap-3 p-3 bg-white/[0.03] border border-white/10 rounded-xl">
                <div className="w-8 h-8 rounded-full bg-amber-500/10 flex items-center justify-center shrink-0">
                  <Lock className="w-4 h-4 text-amber-500" />
                </div>
                <span className="text-xs font-bold text-gray-300 flex-1">Premium required to create custom quick messages.</span>
              </div>
            ) : (
              <>
                {customQuick.length === 0 ? (
                  <p className="text-xs text-gray-500 py-2">No custom messages yet. Add one below.</p>
                ) : (
                  <div className="space-y-1.5 mb-3">
                    {customQuick.map((msg, i) => (
                      <div key={`${i}:${msg}`} className="flex items-center gap-2 bg-brand-surface border border-white/5 rounded-lg px-3 py-2">
                        <SendHorizonal className="w-3.5 h-3.5 text-gray-500 shrink-0" />
                        <span className="text-xs font-bold text-white flex-1 truncate">{msg}</span>
                        <button onClick={() => handleMoveQuickMessage(i, -1)} disabled={i === 0} className="p-1 text-gray-500 hover:text-white disabled:opacity-20"><ChevronUp className="w-3.5 h-3.5" /></button>
                        <button onClick={() => handleMoveQuickMessage(i, 1)} disabled={i === customQuick.length - 1} className="p-1 text-gray-500 hover:text-white disabled:opacity-20"><ChevronDown className="w-3.5 h-3.5" /></button>
                        <button onClick={() => handleDeleteQuickMessage(i)} className="p-1 text-gray-500 hover:text-brand-red"><Trash2 className="w-3.5 h-3.5" /></button>
                      </div>
                    ))}
                  </div>
                )}
                <div className="flex items-center gap-2">
                  <input
                    value={quickInput}
                    maxLength={QUICK_MESSAGE_MAX_CHARS}
                    onChange={(e) => { setQuickInput(e.target.value); setQuickError(''); }}
                    onKeyDown={(e) => { if (e.key === 'Enter' && !savingQuick) handleAddQuickMessage(); }}
                    placeholder="Add custom message…"
                    className="flex-1 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40"
                  />
                  <button
                    onClick={handleAddQuickMessage}
                    disabled={savingQuick || !quickInput.trim()}
                    className="w-10 h-10 shrink-0 rounded-lg bg-brand-lime text-brand-navy flex items-center justify-center disabled:opacity-40"
                  >
                    {savingQuick ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-5 h-5" />}
                  </button>
                </div>
                {quickError && <p className="text-xs font-bold text-brand-red mt-2">{quickError}</p>}
              </>
            )}
          </Glass>
        </div>

        {/* Right Column: Legal + Session + Danger Zone */}
        <div className="space-y-6">
          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <ScrollText className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Legal</h3>
            </div>
            <div className="space-y-1">
              {[
                { href: '/legal/privacy', label: 'Privacy Policy', sub: 'How we collect, use, and protect information.' },
                { href: '/legal/terms', label: 'Terms of Service', sub: 'Rules and conditions for using the app.' },
                { href: '/legal/contact', label: 'Contact', sub: 'Get help or report an issue.' },
                { href: '/legal/affiliate-disclosure', label: 'Affiliate Disclosure', sub: 'How affiliate links work in the marketplace.' },
              ].map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="flex items-center justify-between gap-3 p-3 rounded-xl hover:bg-white/5 transition-colors group"
                >
                  <div className="min-w-0">
                    <p className="text-sm font-bold text-gray-200 group-hover:text-white">{item.label}</p>
                    <p className="text-xs text-gray-500 truncate">{item.sub}</p>
                  </div>
                  <ChevronRight className="w-4 h-4 text-gray-600 shrink-0" />
                </Link>
              ))}
            </div>
          </Glass>

          <Glass className="p-6 flex flex-col items-start gap-4">
            <div className="w-full">
              <h3 className="text-white font-bold text-lg mb-1">Session Management</h3>
              <p className="text-sm text-gray-400">Securely log out of this browser session.</p>
            </div>
            <button
              onClick={handleSignOut}
              className="px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-bold rounded-xl transition-colors flex items-center gap-2 w-full justify-center"
            >
              <LogOut className="w-4 h-4" /> Sign Out
            </button>
          </Glass>

          <Glass className="p-6 border-brand-red/30 bg-brand-red/5">
            <div className="flex items-center gap-2 mb-2">
              <AlertTriangle className="w-5 h-5 text-brand-red" />
              <h3 className="text-brand-red font-bold text-lg">Danger Zone</h3>
            </div>
            <p className="text-sm text-gray-400 mb-6">
              Permanently delete your account. This will erase your profile, team data, and remove you from all leagues. This action cannot be undone.
            </p>
            <button
              onClick={() => setDeleteStep('warning')}
              className="px-6 py-3 bg-brand-red/10 text-brand-red border border-brand-red/30 font-bold rounded-xl hover:bg-brand-red/20 transition-colors flex items-center gap-2 w-full justify-center"
            >
              <UserX className="w-4 h-4" /> Delete Account
            </button>
          </Glass>
        </div>
      </div>

      {/* Step 1 — Warning */}
      {deleteStep === 'warning' && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <Glass className="max-w-md w-full p-8 text-center border-brand-red/50">
            <div className="w-16 h-16 bg-brand-red/20 rounded-full flex items-center justify-center mx-auto mb-4">
              <AlertTriangle className="w-8 h-8 text-brand-red" />
            </div>
            <h3 className="text-2xl font-black text-white mb-2">Close Account?</h3>
            <div className="text-left text-sm text-gray-400 mb-6 space-y-2 bg-brand-red/5 border border-brand-red/15 rounded-xl p-4">
              <p>⚠ This action is permanent and cannot be undone.</p>
              <p>☁ All your personal data, matches, and stats will be wiped.</p>
              <p>🏆 Your leagues and tournament access will be lost.</p>
            </div>
            <div className="flex gap-3">
              <button onClick={() => setDeleteStep('idle')} className="flex-1 py-3 bg-brand-surface border border-white/10 rounded-xl text-white font-bold hover:bg-white/5 transition-colors">
                Cancel — Keep My Account
              </button>
              <button onClick={() => setDeleteStep('feedback')} className="flex-1 py-3 bg-brand-red text-white font-bold rounded-xl hover:bg-brand-red/90 transition-colors shadow-lg shadow-brand-red/20">
                Yes, Close My Account
              </button>
            </div>
          </Glass>
        </div>
      )}

      {/* Step 2 — Feedback */}
      {deleteStep === 'feedback' && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <Glass className="max-w-md w-full p-6 relative max-h-[90vh] overflow-y-auto">
            <button onClick={() => setDeleteStep('idle')} className="absolute top-4 right-4 w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300">
              <X className="w-4 h-4" />
            </button>
            <h3 className="text-lg font-black text-white mb-1">We&apos;re sad to see you go</h3>
            <p className="text-xs text-gray-400 mb-5">Please tell us why so we can improve.</p>

            <p className="text-sm font-bold text-gray-200 mb-2">Select all that apply:</p>
            <div className="space-y-2 mb-4">
              {FEEDBACK_REASONS.map((reason) => {
                const selected = selectedReasons.has(reason);
                return (
                  <button
                    key={reason}
                    onClick={() => toggleReason(reason)}
                    className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl border text-left transition-colors ${selected ? 'bg-brand-lime/15 border-brand-lime/50' : 'bg-white/[0.03] border-white/10 hover:bg-white/5'}`}
                  >
                    {selected ? <Check className="w-4 h-4 text-brand-lime shrink-0" /> : <Circle className="w-4 h-4 text-gray-500 shrink-0" />}
                    <span className={`text-xs font-bold ${selected ? 'text-white' : 'text-gray-400'}`}>{reason}</span>
                  </button>
                );
              })}
            </div>

            <p className="text-sm font-bold text-gray-200 mb-2">Tell us more (Optional):</p>
            <textarea
              value={feedbackText}
              maxLength={500}
              rows={3}
              onChange={(e) => setFeedbackText(e.target.value)}
              placeholder="Any additional feedback..."
              className="w-full px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40 resize-none mb-5"
            />

            <div className="flex gap-3">
              <button onClick={handleSkipFeedback} className="flex-1 py-3 text-gray-400 font-bold text-sm hover:text-white transition-colors">
                Skip
              </button>
              <button onClick={handleSubmitFeedback} className="flex-[2] py-3 bg-brand-red text-white font-bold rounded-xl hover:bg-brand-red/90 transition-colors">
                Close Account
              </button>
            </div>
          </Glass>
        </div>
      )}

      {/* Step 3 — Deleting */}
      {deleteStep === 'deleting' && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <Glass className="max-w-md w-full p-8 text-center">
            <Loader2 className="w-12 h-12 text-brand-red animate-spin mb-4 mx-auto" />
            <h3 className="text-xl font-bold text-white mb-2">Closing Account</h3>
            <p className="text-sm text-gray-400">Removing your data permanently. Please wait...</p>
          </Glass>
        </div>
      )}
    </div>
  );
}

function ToggleRow({ label, checked, onChange, disabled = false }: { label: string, checked: boolean, onChange: () => void, disabled?: boolean }) {
  return (
    <div className={`flex items-center justify-between p-3 bg-brand-surface rounded-xl border border-white/5 ${disabled ? 'opacity-50' : ''}`}>
      <span className="text-sm font-bold text-gray-200">{label}</span>
      <div
        onClick={disabled ? undefined : onChange}
        className={`w-12 h-6 rounded-full p-1 transition-colors ${disabled ? 'cursor-not-allowed' : 'cursor-pointer'} ${checked ? 'bg-brand-lime' : 'bg-gray-600'}`}
      >
        <div className={`w-4 h-4 rounded-full bg-brand-navy transition-transform ${checked ? 'translate-x-6' : 'translate-x-0'}`} />
      </div>
    </div>
  );
}
