
//create/page.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useEntitlements, canCreateWorkspace } from '@/hooks/useEntitlements';
import { create as createWorkspace } from '@/lib/masterLeagues/masterLeaguesRepository';
import { payForPlanSubscription } from '@/lib/masterLeagues/masterLeaguePayments';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import { Loader2, ArrowLeft, Network, ShieldCheck, Star, Crown, ShieldAlert, Check } from 'lucide-react';
import {
  MASTER_LEAGUE_PLANS,
  MasterLeaguePlanId,
  PLAN_DURATIONS,
  PlanDurationId,
  planOrder,
} from '@/types/masterLeague';

// Corrected Plan Colors
const PLAN_TINT: Record<MasterLeaguePlanId, string> = {
  basic: '#B8E928',
  pro: '#38BDF8',
  elite: '#F59E0B',
};

const PLAN_ICON: Record<MasterLeaguePlanId, any> = {
  basic: ShieldCheck,
  pro: Star,
  elite: Crown,
};

export default function CreateMasterLeagueScreen() {
  const router = useRouter();
  const { activePlan, ownedCount, loading: entLoading, refresh } = useEntitlements();

  const [hubName, setHubName] = useState('');
  const [selectedPlan, setSelectedPlan] = useState<MasterLeaguePlanId>('basic');
  const [selectedDuration, setSelectedDuration] = useState<PlanDurationId>('3mo');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const selectedDef = MASTER_LEAGUE_PLANS[selectedPlan];
  const needsPayment = !selectedDef.isFree && planOrder(activePlan) < planOrder(selectedPlan);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    const name = hubName.trim();
    if (!name) return setError('Hub name is required.');
    if (name.length > 60) return setError('Hub name is too long.');

    setLoading(true);
    try {
      const canCreateNow = canCreateWorkspace(needsPayment ? selectedPlan : activePlan, ownedCount);

      if (needsPayment) {
        const payResult = await payForPlanSubscription(selectedPlan, selectedDuration);
        if (!payResult.success) {
          setError(payResult.errorMessage || 'Payment failed.');
          setLoading(false);
          return;
        }
        await refresh();
      } else if (!canCreateNow) {
        throw new Error('You have reached the workspace limit for your current plan. Please select a higher plan.');
      }

      const created = await createWorkspace({ name, plan: selectedPlan });
      router.push(`/master-leagues/${created.id}`);
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'Something went wrong.');
    } finally {
      setLoading(false);
    }
  };

  if (entLoading) {
    return (
      <div className="flex justify-center py-32">
        <Loader2 className="w-9 h-9 animate-spin text-[#38BDF8]" />
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto pb-16 space-y-6">
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <div className="absolute -top-40 left-1/4 w-[500px] h-[500px] rounded-full bg-[#38BDF8]/[0.05] blur-[120px]" />
        <div className="absolute top-40 right-1/3 w-[400px] h-[400px] rounded-full bg-brand-lime/[0.05] blur-[120px]" />
      </div>

      <div className="flex items-center gap-4">
        <button
          onClick={() => router.back()}
          className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-2">
            <Network className="w-6 h-6 text-[#38BDF8]" /> Create Master League
          </h1>
          <p className="text-gray-500 text-sm mt-0.5">Establish your eSports Organizer Hub.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-4">
          <h2 className="text-xs font-black uppercase tracking-widest text-gray-500 px-1">Select Hub Tier</h2>

          {Object.values(MASTER_LEAGUE_PLANS).map((plan) => {
            const Icon = PLAN_ICON[plan.id];
            const tint = PLAN_TINT[plan.id];
            const selected = selectedPlan === plan.id;
            const isCurrent = activePlan === plan.id;

            return (
              <div
                key={plan.id}
                onClick={() => setSelectedPlan(plan.id)}
                className="p-4 rounded-2xl border cursor-pointer transition-all relative overflow-hidden"
                style={{
                  background: selected ? `${tint}0D` : '#0B1221',
                  borderColor: selected ? `${tint}55` : '#1E293B',
                }}
              >
                <div className="flex items-center gap-2.5 mb-2">
                  <div
                    className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0 border"
                    style={{ background: `${tint}1A`, borderColor: `${tint}33` }}
                  >
                    <Icon className="w-4 h-4" style={{ color: tint }} />
                  </div>
                  <span className="font-bold text-white text-sm">
                    {plan.displayName} {plan.isFree ? '(Free)' : ''}
                  </span>
                  {selected && <Check className="w-4 h-4 ml-auto" style={{ color: tint }} />}
                  {isCurrent && !selected && (
                    <span className="ml-auto text-[9px] font-black uppercase tracking-wider text-gray-500 bg-white/5 px-2 py-0.5 rounded">
                      Current
                    </span>
                  )}
                </div>
                <p className="text-xs text-gray-500 leading-relaxed">{plan.description}</p>
                {!plan.isFree && planOrder(activePlan) < planOrder(plan.id) && (
                  <div
                    className="mt-3 text-center w-full py-1.5 rounded-lg text-[10px] font-black uppercase tracking-wider"
                    style={{ background: `${tint}14`, color: tint }}
                  >
                    Requires Payment
                  </div>
                )}
              </div>
            );
          })}

          {needsPayment && (
            <div className="pt-2 space-y-2">
              <h3 className="text-xs font-black uppercase tracking-widest text-gray-500 px-1">Duration</h3>
              {Object.values(PLAN_DURATIONS).map((d) => (
                <div
                  key={d.id}
                  onClick={() => setSelectedDuration(d.id)}
                  className={`flex items-center justify-between p-3 rounded-xl border cursor-pointer transition-all ${
                    selectedDuration === d.id
                      ? 'bg-brand-lime/10 border-brand-lime/40'
                      : 'bg-[#0B1221] border-[#1E293B] hover:border-[#2A3A52]'
                  }`}
                >
                  <span className="text-sm font-bold text-white">{d.displayName}</span>
                  {d.discountLabel && (
                    <span className="text-[10px] font-black text-brand-lime bg-brand-lime/10 px-2 py-0.5 rounded">
                      {d.discountLabel}
                    </span>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="lg:col-span-2">
          <PanelCard className="h-full">
            {error && (
              <div className="flex items-center gap-2 bg-brand-red/10 border border-brand-red/30 text-brand-red p-4 rounded-xl mb-6 text-sm">
                <ShieldAlert className="w-5 h-5 flex-shrink-0" />
                {error}
              </div>
            )}

            <form onSubmit={handleCreate} className="space-y-6">
              <div>
                <label className="block text-xs font-bold uppercase tracking-wider text-gray-500 mb-2">
                  Hub Name (Your Brand) *
                </label>
                <input
                  type="text"
                  value={hubName}
                  onChange={(e) => setHubName(e.target.value)}
                  required
                  maxLength={60}
                  placeholder="e.g. Continental eSports"
                  className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-4 text-white placeholder:text-gray-600 focus:outline-none focus:border-[#38BDF8]/50 transition-colors"
                />
              </div>

              <div className="pt-6 border-t border-[#1E293B]">
                <button
                  type="submit"
                  disabled={loading || !hubName.trim()}
                  className="w-full py-4 bg-brand-lime text-brand-navy font-black rounded-xl hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-brand-lime/20"
                >
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Network className="w-5 h-5" />}
                  {needsPayment ? 'Pay & Create Hub' : 'Initialize Hub'}
                </button>
                <p className="text-[11px] text-gray-600 mt-3 text-center">
                  Card and Google Pay accepted via Flutterwave. No Google Play fee on web.
                </p>
              </div>
            </form>
          </PanelCard>
        </div>
      </div>
    </div>
  );
}
