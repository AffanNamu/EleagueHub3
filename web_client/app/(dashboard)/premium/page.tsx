'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { getRemotePricingPlan, getPlanPrice, RemotePricingPlan } from '@/lib/masterLeagues/pricing';
import { payForPlanSubscription } from '@/lib/masterLeagues/masterLeaguePayments';
import { MasterLeaguePlanId, PlanDurationId } from '@/types/masterLeague';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Crown, CheckCircle2 } from 'lucide-react';

const PLANS: { id: MasterLeaguePlanId; displayName: string; isFree: boolean; features: string[] }[] = [
  { id: 'basic', displayName: 'Basic', isFree: true, features: ['1 master league workspace', 'Up to 3 competitions', 'Standard organizer tools'] },
  { id: 'pro', displayName: 'Pro', isFree: false, features: ['5 master league workspaces', 'Up to 9 competitions per workspace', 'Pro organizer badge', 'Priority support'] },
  { id: 'elite', displayName: 'Elite', isFree: false, features: ['Unlimited master league workspaces', 'Unlimited competitions', 'Elite organizer badge', 'Maximum competition capacity', 'Priority support'] },
];

const DURATIONS: { id: PlanDurationId; displayName: string; discount: string }[] = [
  { id: '1mo', displayName: '1 Month', discount: '' },
  { id: '3mo', displayName: '3 Months', discount: '' },
  { id: '6mo', displayName: '6 Months', discount: 'Save 10%' },
  { id: 'yearly', displayName: '1 Year', discount: 'Save 25%' },
];

export default function UpgradePlanScreen() {
  const router = useRouter();
  const [selectedPlan, setSelectedPlan] = useState(PLANS[1]); // Default to Pro
  const [selectedDuration, setSelectedDuration] = useState(DURATIONS[0]);

  const [pricingConfig, setPricingConfig] = useState<RemotePricingPlan | null>(null);
  const [loadingPrice, setLoadingPrice] = useState(true);
  const [currentPrice, setCurrentPrice] = useState<number | null>(null);
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch remote pricing once (country-resolved currency + all plan fees).
  useEffect(() => {
    async function loadPricing() {
      try {
        const conf = await getRemotePricingPlan();
        setPricingConfig(conf);
      } catch (err) {
        console.error('Pricing load failed', err);
      } finally {
        setLoadingPrice(false);
      }
    }
    loadPricing();
  }, []);

  // Re-resolve the exact price whenever the selected plan/duration changes.
  useEffect(() => {
    if (selectedPlan.isFree) return;
    let cancelled = false;
    getPlanPrice(selectedPlan.id, selectedDuration.id).then((price) => {
      if (!cancelled) setCurrentPrice(price?.amount ?? 0);
    });
    return () => {
      cancelled = true;
    };
  }, [selectedPlan, selectedDuration]);

  const displayPrice = selectedPlan.isFree ? 0 : currentPrice;
  const currencySymbol = pricingConfig?.currency === 'NGN' ? '₦' : '$';
  const formattedPrice =
    displayPrice == null ? '' : displayPrice % 1 === 0 ? displayPrice.toFixed(0) : displayPrice.toFixed(2);

  const getAccentColor = (planId: string) => {
    if (planId === 'elite') return 'text-purple-500 bg-purple-500';
    if (planId === 'basic') return 'text-gray-400 bg-gray-400';
    return 'text-[#BEF264] bg-[#BEF264]';
  };

  const handlePayment = async () => {
    if (processing || selectedPlan.isFree) return;
    if (!auth.currentUser) return setError('Please sign in before purchasing a plan.');

    setProcessing(true);
    setError(null);

    try {
      const result = await payForPlanSubscription(selectedPlan.id, selectedDuration.id);
      if (!result.success) {
        setError(result.errorMessage || 'Payment failed.');
        return;
      }

      alert('Plan upgraded successfully!');
      router.push('/master-leagues');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Payment failed.');
    } finally {
      setProcessing(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6 pb-24 px-4 sm:px-6">

      <div className="flex items-center gap-4 mt-4 mb-2">
        <button onClick={() => router.back()} disabled={processing} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl font-black text-white">Upgrade Your Plan</h1>
      </div>

      <div className="flex flex-col items-center justify-center pt-4 pb-2">
        <div className={`w-16 h-16 rounded-full flex items-center justify-center mb-4 ${getAccentColor(selectedPlan.id).split(' ')[0].replace('text', 'bg')}/10 border border-${getAccentColor(selectedPlan.id).split(' ')[0].replace('text', 'border')}/30`}>
          <Crown className={`w-8 h-8 ${getAccentColor(selectedPlan.id).split(' ')[0]}`} />
        </div>
      </div>

      {/* ── PLAN TABS ── */}
      <Glass className="p-1 flex gap-2 border-[#1E293B] bg-[#0B1221] rounded-2xl">
        {PLANS.map(plan => (
          <button
            key={plan.id}
            onClick={() => setSelectedPlan(plan)}
            className={`flex-1 py-3 text-sm font-black rounded-xl transition-all ${selectedPlan.id === plan.id ? `${getAccentColor(plan.id).split(' ')[1]} text-[#0F172A] shadow-md` : 'text-gray-400 hover:text-white'}`}
          >
            {plan.displayName}
          </button>
        ))}
      </Glass>

      {/* ── FEATURES LIST ── */}
      <Glass className="p-6 border-[#1E293B] bg-[#0B1221] rounded-3xl shadow-xl">
        <div className="space-y-4">
          {selectedPlan.features.map((feat, idx) => (
            <div key={idx} className="flex items-start gap-3">
              <CheckCircle2 className={`w-5 h-5 mt-0.5 shrink-0 ${getAccentColor(selectedPlan.id).split(' ')[0]}`} />
              <p className="text-white font-bold text-sm leading-relaxed">{feat}</p>
            </div>
          ))}
        </div>
      </Glass>

      {/* ── DURATIONS / FREE TIER NOTIFICATION ── */}
      {selectedPlan.isFree ? (
        <div className="p-4 rounded-2xl bg-[#1E293B]/50 border border-[#1E293B] text-center text-sm font-bold text-gray-300">
          Basic is your free starter plan and requires no payment.
        </div>
      ) : (
        <div className="space-y-3">
          <h3 className="text-sm font-black text-white ml-2">Choose Duration</h3>
          {DURATIONS.map(dur => (
            <button
              key={dur.id}
              onClick={() => setSelectedDuration(dur)}
              className={`w-full p-4 rounded-2xl border text-left flex items-center transition-all ${selectedDuration.id === dur.id ? `bg-[#1E293B] ${getAccentColor(selectedPlan.id).split(' ')[0].replace('text', 'border')}` : 'bg-[#0B1221] border-[#1E293B]'}`}
            >
              <div className={`w-5 h-5 rounded-full border-2 mr-4 flex items-center justify-center ${selectedDuration.id === dur.id ? getAccentColor(selectedPlan.id).split(' ')[0].replace('text', 'border') : 'border-gray-500'}`}>
                {selectedDuration.id === dur.id && <div className={`w-2.5 h-2.5 rounded-full ${getAccentColor(selectedPlan.id).split(' ')[1]}`} />}
              </div>
              <span className="flex-1 font-black text-white text-sm">{dur.displayName}</span>
              {dur.discount && <span className="px-2.5 py-1 rounded-lg bg-green-500/20 text-green-500 text-[10px] font-black uppercase tracking-widest">{dur.discount}</span>}
            </button>
          ))}
        </div>
      )}

      {error && (
        <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm font-bold text-center">
          {error}
        </div>
      )}

      {/* ── BOTTOM STICKY CHECKOUT BAR ── */}
      {!selectedPlan.isFree && (
        <div className="fixed bottom-0 left-0 right-0 p-4 bg-[#0B1221] border-t border-[#1E293B] z-50">
          <div className="max-w-2xl mx-auto flex items-center justify-between">
            <div>
              {loadingPrice || displayPrice == null ? (
                <Loader2 className="w-5 h-5 animate-spin text-gray-500" />
              ) : (
                <div className="text-2xl font-black text-white">{currencySymbol}{formattedPrice}</div>
              )}
              <div className="text-xs font-bold text-gray-500">{selectedDuration.displayName}</div>
            </div>

            <button
              onClick={handlePayment}
              disabled={processing || loadingPrice}
              className={`px-8 py-3.5 rounded-xl font-black flex items-center gap-2 transition-transform active:scale-95 disabled:opacity-50 ${getAccentColor(selectedPlan.id).split(' ')[1]} ${selectedPlan.id === 'elite' ? 'text-white' : 'text-[#0F172A]'}`}
            >
              {processing ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Subscribe & Pay'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
