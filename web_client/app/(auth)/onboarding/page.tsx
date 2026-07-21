'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Glass } from '@/components/ui/Glass';
import { GlassScaffold } from '@/components/ui/GlassScaffold';
import { Loader2, Gamepad2, Smartphone, ChevronLeft } from 'lucide-react';

const GAME_GROUPS = [
  {
    label: 'Console / PC',
    icon: Gamepad2,
    games: [
      'EA Sports FC 25',
      'FIFA 23',
      'eFootball',
      'PES 2021',
      'PES 2017',
      'UFL',
      'Rocket League',
    ],
  },
  {
    label: 'Mobile',
    icon: Smartphone,
    games: [
      'EA Sports FC Mobile',
      'Dream League Soccer',
      'Soccer Stars',
      'Total Football',
      'Football Strike',
      'Mini Football',
      'Score! Match',
    ],
  },
] as const;

const EXPERIENCE_LEVELS = [
  'Beginner',
  'Intermediate',
  'Professional',
  'Tournament Organizer',
] as const;

function deriveShareIdFromUid(uid: string): string {
  const clean = uid.replace(/[^A-Za-z0-9]/g, '').trim();
  if (!clean) return '';
  const base = clean.length >= 8 ? clean.slice(0, 8) : clean.padEnd(8, 'X');
  return `eS${base}`;
}

export default function OnboardingScreen() {
  const router = useRouter();
  const goalRef = useRef<HTMLTextAreaElement>(null);

  const [checking, setChecking] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [step, setStep] = useState(0);

  const [teamName, setTeamName] = useState('');
  const [game, setGame] = useState('');
  const [experience, setExperience] = useState('');
  const [goal, setGoal] = useState('');

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (!user) {
        router.push('/login');
        return;
      }
      try {
        const snap = await getDoc(doc(db, 'users', user.uid));
        if (snap.exists()) {
          router.push('/leagues');
          return;
        }
      } catch (err) {
        console.error('Failed to check onboarding status', err);
      }
      setChecking(false);
    });

    return () => unsubscribe();
  }, [router]);

  const canContinueStep0 = teamName.trim().length > 0;
  const canContinueStep1 = game.trim().length > 0;
  const canContinueStep2 = experience.trim().length > 0;

  const goNext = () => {
    if (step === 0 && canContinueStep0) return setStep(1);
    if (step === 1 && canContinueStep1) return setStep(2);
    if (step === 2 && canContinueStep2) return setStep(3);
    if (step === 3) return handleFinish();
  };

  const goBack = () => {
    if (step === 0) return router.back();
    setStep((s) => s - 1);
  };

  const handleFinish = async () => {
    const user = auth.currentUser;
    if (!user) {
      router.push('/login');
      return;
    }
    if (!teamName.trim()) {
      setError('Please enter your club or gamer name.');
      setStep(0);
      return;
    }

    setSaving(true);
    setError('');

    try {
      const uid = user.uid;
      const ref = doc(db, 'users', uid);

      const existing = await getDoc(ref);
      if (existing.exists()) {
        router.push('/leagues');
        return;
      }

      const nowMs = Date.now();
      const providerId = user.providerData[0]?.providerId ?? '';
      const authProvider = providerId.includes('google')
        ? 'google'
        : providerId === 'password'
          ? 'email'
          : providerId || 'unknown';

      await setDoc(ref, {
        userId: uid,
        teamName: teamName.trim(),
        authProvider,
        createdAt: nowMs,
        updatedAt: nowMs,
        shareId: deriveShareIdFromUid(uid),
        activePlanId: '',
        activePlanDurationId: '',
        planPurchasedAtMs: 0,
        planExpiresAtMs: 0,
        planReceiptId: '',
        planProvider: '',
      });

      router.push('/leagues');
    } catch (err: any) {
      console.error(err);
      setError('Failed to save your profile: ' + (err?.message ?? 'Unknown error'));
      setSaving(false);
    }
  };

  if (checking) {
    return (
      <GlassScaffold>
        <div className="flex items-center justify-center min-h-[80vh]">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      </GlassScaffold>
    );
  }

  const stepTitles = ['Identity', 'Football Platform', 'Experience Level', 'Your Goal'];

  return (
    <GlassScaffold>
      <div className="flex items-center justify-center min-h-[85vh] py-10 px-4">
        <Glass className="w-full max-w-2xl p-6 md:p-10">
          <div className="flex items-center gap-2 mb-8">
            {stepTitles.map((title, i) => (
              <div key={title} className="flex-1">
                <div
                  className={`h-1.5 rounded-full transition-colors ${
                    i <= step ? 'bg-brand-lime' : 'bg-white/10'
                  }`}
                />
              </div>
            ))}
          </div>

          <div className="mb-8">
            <p className="text-brand-lime text-xs font-black uppercase tracking-widest mb-1">
              Step {step + 1} of {stepTitles.length}
            </p>
            <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight">
              {stepTitles[step]}
            </h1>
          </div>

          {error && (
            <div className="bg-brand-red/20 border border-brand-red text-brand-red p-3 rounded-lg mb-6 text-sm text-center">
              {error}
            </div>
          )}

          {step === 0 && (
            <div className="space-y-3">
              <label className="block text-sm font-bold text-gray-300">
                Club / Gamer Name
              </label>
              <input
                type="text"
                value={teamName}
                onChange={(e) => setTeamName(e.target.value)}
                placeholder="Example: Galaxy FC"
                className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:outline-none focus:border-brand-lime transition-colors font-medium"
                maxLength={40}
                autoFocus
              />
              <p className="text-xs text-gray-500">
                Create your football gaming identity on eSportlyic.
              </p>
            </div>
          )}

          {step === 1 && (
            <div className="space-y-6">
              {GAME_GROUPS.map((group) => (
                <div key={group.label}>
                  <div className="flex items-center gap-2 mb-3">
                    <group.icon className="w-4 h-4 text-gray-400" />
                    <span className="text-xs font-bold uppercase tracking-wide text-gray-400">
                      {group.label}
                    </span>
                    <div className="flex-1 h-px bg-white/10" />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {group.games.map((g) => (
                      <button
                        key={g}
                        type="button"
                        onClick={() => setGame(g)}
                        className={`px-4 py-2 rounded-full border text-sm font-semibold transition-all ${
                          game === g
                            ? 'bg-brand-lime border-brand-lime text-slate-900'
                            : 'bg-white/5 border-white/10 text-gray-300 hover:bg-white/10'
                        }`}
                      >
                        {g}
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}

          {step === 2 && (
            <div className="flex flex-wrap gap-2">
              {EXPERIENCE_LEVELS.map((lvl) => (
                <button
                  key={lvl}
                  type="button"
                  onClick={() => setExperience(lvl)}
                  className={`px-4 py-2 rounded-full border text-sm font-semibold transition-all ${
                    experience === lvl
                      ? 'bg-brand-lime border-brand-lime text-slate-900'
                      : 'bg-white/5 border-white/10 text-gray-300 hover:bg-white/10'
                  }`}
                >
                  {lvl}
                </button>
              ))}
            </div>
          )}

          {step === 3 && (
            <div className="space-y-3">
              <label className="block text-sm font-bold text-gray-300">
                What brings you here?
              </label>
              <textarea
                ref={goalRef}
                value={goal}
                onChange={(e) => setGoal(e.target.value)}
                rows={4}
                placeholder="Example: Compete in tournaments, grow my club, organize leagues, stream matches..."
                className="w-full bg-brand-surface border border-white/10 rounded-xl p-4 text-white focus:outline-none focus:border-brand-lime transition-colors font-medium resize-none"
              />
            </div>
          )}

          <div className="flex items-center gap-3 mt-10">
            <button
              type="button"
              onClick={goBack}
              disabled={saving}
              className="flex items-center gap-1 px-4 py-3 rounded-xl text-gray-400 hover:text-white hover:bg-white/5 font-bold text-sm transition-all disabled:opacity-50"
            >
              <ChevronLeft className="w-4 h-4" />
              {step === 0 ? 'Close' : 'Back'}
            </button>

            <button
              type="button"
              onClick={goNext}
              disabled={
                saving ||
                (step === 0 && !canContinueStep0) ||
                (step === 1 && !canContinueStep1) ||
                (step === 2 && !canContinueStep2)
              }
              className="flex-1 bg-brand-lime text-slate-900 font-black py-3.5 rounded-xl hover:bg-brand-lime/90 transition-all disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {saving ? (
                <Loader2 className="w-5 h-5 animate-spin" />
              ) : step === 3 ? (
                'Complete Setup'
              ) : (
                'Continue'
              )}
            </button>
          </div>
        </Glass>
      </div>
    </GlassScaffold>
  );
}
