import React, { useState } from 'react';
import { League } from '@/types/league';
import { useLeagueAccess } from '@/hooks/useLeagueAccess';
import { useCouponRedemption } from '@/hooks/useCouponRedemption';
import { payWithFlutterwave } from '@/lib/payments/flutterwavePay';
import { getRemotePricingPlan } from '@/lib/payments/remotePricing';

import { Glass } from '@/components/ui/Glass';
import { Loader2, Lock, Key, ShieldAlert } from 'lucide-react';

export const LeagueAccessGate = ({ league, children }: { league: League, children: React.ReactNode }) => {
  const { status, error: accessError } = useLeagueAccess(league);
  const { redeemCoupon, redeeming, error: couponError } = useCouponRedemption(league.id);
  const [code, setCode] = useState('');

  const [paying, setPaying] = useState(false);
  const [payError, setPayError] = useState<string | null>(null);

  const handlePayEntryFee = async () => {
    setPaying(true);
    setPayError(null);

    try {
      const plan = await getRemotePricingPlan();

      if (!plan.paymentsEnabled) {
        setPayError('Payments are temporarily disabled by the administrator.');
        return;
      }
      if (!plan.flutterwaveEnabled) {
        setPayError('Flutterwave payments are currently unavailable.');
        return;
      }

      const fee = plan.accessFee;
      if (fee <= 0) {
        setPayError('League access price is not configured correctly.');
        return;
      }

      const result = await payWithFlutterwave({
        amount: fee,
        currency: plan.currency,
        leagueId: league.id,
        leagueName: league.name,
        productType: 'league_access',
        productSubType: 'league_standard_access',
        description: `League access: ${league.name}`,
        items: [
          {
            productType: 'league_access',
            productSubType: 'league_standard_access',
            quantity: 1,
            amount: fee,
          },
        ],
        // Payment method (card vs googlepay) recorded for analytics only.
        metadata: {},
      });

      if (!result.success) {
        setPayError(result.errorMessage || 'Payment failed.');
        return;
      }

      window.location.reload(); // Reload to pass the access gate
    } catch (e) {
      setPayError(e instanceof Error ? e.message : 'Payment failed.');
    } finally {
      setPaying(false);
    }
  };


  if (status === 'loading') {
    return <div className="flex justify-center py-40"><Loader2 className="w-10 h-10 animate-spin text-brand-lime" /></div>;
  }

  if (status === 'allowed') {
    return <>{children}</>;
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] p-4">
      <Glass className="max-w-md w-full p-8 text-center flex flex-col items-center">
        <Lock className="w-16 h-16 text-brand-red mb-4" />
        <h2 className="text-2xl font-black text-white mb-2">Private Tournament</h2>
        <p className="text-gray-400 text-sm mb-6">
          {accessError || `You must pay the entry fee or redeem a coupon to unlock ${league.name}.`}
        </p>

        {couponError && (
          <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-3 rounded-lg mb-4 w-full text-left text-xs">
            <ShieldAlert className="w-4 h-4 shrink-0" /> {couponError}
          </div>
        )}

        {/* Coupon Entry */}
        <div className="w-full space-y-3 mb-6">
          <div className="relative">
            <Key className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input 
              type="text" 
              value={code} 
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="ENTER COUPON CODE" 
              className="w-full pl-9 pr-4 py-3 bg-brand-surface border border-white/10 rounded-xl text-white font-mono focus:border-brand-lime"
            />
          </div>
          <button 
            onClick={() => redeemCoupon(code)}
            disabled={redeeming || code.length < 6}
            className="w-full py-3 bg-white/10 hover:bg-white/20 text-white font-bold rounded-xl transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {redeeming ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Redeem Code'}
          </button>
        </div>

        <div className="flex items-center w-full gap-3 text-gray-500 mb-6">
          <div className="h-px bg-white/10 flex-1"></div>
          <span className="text-xs font-bold uppercase">OR</span>
          <div className="h-px bg-white/10 flex-1"></div>
        </div>

        {payError && <div className="text-brand-red text-xs mb-2">{payError}</div>}
        <button 
          onClick={handlePayEntryFee}
          disabled={paying}
          className="w-full py-3 bg-brand-lime text-brand-navy font-black rounded-xl hover:bg-brand-lime/90 transition-colors shadow-lg shadow-brand-lime/20 disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {paying ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Pay Entry Fee'}
        </button>
        <p className="text-[10px] text-gray-500 mt-3">Card and Google Pay accepted via Flutterwave.</p>
    
      </Glass>
    </div>
  );
};
