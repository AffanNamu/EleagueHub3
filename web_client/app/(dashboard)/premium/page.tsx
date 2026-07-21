'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth, db } from '@/lib/firebase';
import { doc, setDoc } from 'firebase/firestore';
import { Check, Crown, Zap, Loader2 } from 'lucide-react';

export default function PremiumScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [scriptLoaded, setScriptLoaded] = useState(false);

  // 1. Dynamically load the Flutterwave V3 script securely
  useEffect(() => {
    const script = document.createElement('script');
    script.src = 'https://checkout.flutterwave.com/v3.js';
    script.async = true;
    script.onload = () => setScriptLoaded(true);
    document.body.appendChild(script);

    return () => {
      document.body.removeChild(script);
    };
  }, []);

  // 2. The main payment handler
  const handleUpgrade = async (tier: 'pro' | 'elite') => {
    const user = auth.currentUser;
    if (!user) {
      alert("Please log in to upgrade.");
      router.push('/login');
      return;
    }

    if (!scriptLoaded || typeof window === 'undefined' || !(window as any).FlutterwaveCheckout) {
      alert("Payment gateway is still loading. Please try again in a second.");
      return;
    }

    const price = tier === 'pro' ? 9.99 : 24.99;
    const planName = tier === 'pro' ? 'Pro Organizer' : 'Elite Organizer';

    // BRO: PUT YOUR REAL FLUTTERWAVE PUBLIC KEY HERE!
    const FLW_PUBLIC_KEY = process.env.NEXT_PUBLIC_FLUTTERWAVE_PUBLIC_KEY || "FLWPUBK_TEST-xxxxxxxxxxxxxxxxxxxxx-X";

    (window as any).FlutterwaveCheckout({
      public_key: FLW_PUBLIC_KEY,
      tx_ref: `upgrade_${tier}_${user.uid}_${Date.now()}`,
      amount: price,
      currency: "USD",
      payment_options: "card, mobilemoney, ussd",
      customer: {
        email: user.email || "user@esportlyic.com",
        name: user.displayName || "Organizer",
      },
      customizations: {
        title: "eSportlyic Premium",
        description: `Upgrade to ${planName}`,
        logo: "https://esportlyic.web.app/icon.png", // Point to your actual logo
      },
      callback: async (data: any) => {
        // This runs when the payment is successful
        if (data.status === "successful" || data.status === "completed") {
          setLoading(true);
          try {
            // Update Firestore exactly like your Flutter BadgeService
            const badgeUpdate = {
              verification: {
                greenVerified: true,
                greenSource: tier === 'pro' ? 'pro_subscription' : 'elite_subscription',
                // If they bought Elite, they also get the Organizer badge!
                organizerVerified: tier === 'elite',
                organizerSource: tier === 'elite' ? 'elite_subscription' : null,
              }
            };

            await setDoc(doc(db, 'users', user.uid), badgeUpdate, { merge: true });
            
            alert(`Payment successful! Welcome to the ${planName} tier.`);
            router.push('/profile'); // Redirect back to profile to see the new badges!
          } catch (err) {
            console.error("Error updating user badge:", err);
            alert("Payment processed, but we had an issue updating your account. Contact support.");
          } finally {
            setLoading(false);
          }
        }
      },
      onclose: () => {
        // Handle when they close the modal without paying
        setLoading(false);
      },
    });
  };

  return (
    <div className="space-y-8 pb-10">
      <div className="text-center max-w-2xl mx-auto pt-8">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-amber-500/10 border border-amber-500/30 mb-6 shadow-[0_0_15px_rgba(245,158,11,0.2)]">
          <Crown className="w-8 h-8 text-amber-500" />
        </div>
        <h1 className="text-3xl md:text-5xl font-black text-white tracking-tight mb-4">
          Unlock <span className="text-transparent bg-clip-text bg-gradient-to-r from-amber-400 to-amber-600">Elite</span> Power
        </h1>
        <p className="text-gray-400 text-lg">
          Take your leagues to the next level with advanced analytics, custom branding, and unlimited participants.
        </p>
      </div>

      <div className="flex flex-col md:flex-row gap-6 max-w-4xl mx-auto justify-center px-4">
        
        {/* Pro Tier */}
        <div className="flex-1 bg-[#0B1221] border border-[#1E293B] rounded-2xl p-8 border-t-4 border-t-[#38BDF8] flex flex-col">
          <h3 className="text-xl font-bold text-white mb-2">Pro Organizer</h3>
          <div className="flex items-end gap-1 mb-6">
            <span className="text-4xl font-black text-white">$9.99</span>
            <span className="text-gray-400 mb-1 font-bold">/mo</span>
          </div>
          <ul className="space-y-4 mb-8 flex-1">
            {['Up to 5 Active Leagues', 'Advanced Standings Engine', 'Basic Analytics', 'Standard Support', 'Green Verified Badge'].map((feature, i) => (
              <li key={i} className="flex items-center gap-3 text-sm text-gray-300 font-medium">
                <Check className="w-5 h-5 text-[#38BDF8]" /> {feature}
              </li>
            ))}
          </ul>
          <button 
            onClick={() => handleUpgrade('pro')} 
            disabled={loading || !scriptLoaded}
            className="w-full py-3.5 bg-[#0F172A] hover:bg-[#1E293B] text-white font-bold rounded-xl border border-[#38BDF8]/30 hover:border-[#38BDF8] transition-all flex justify-center items-center gap-2"
          >
            {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Get Pro'}
          </button>
        </div>

        {/* Elite Tier */}
        <div className="flex-1 bg-[#0B1221] border border-amber-500/30 rounded-2xl p-8 border-t-4 border-t-amber-500 transform md:-translate-y-4 shadow-[0_10px_40px_rgba(245,158,11,0.1)] relative overflow-hidden flex flex-col">
          <div className="absolute top-0 right-0 bg-amber-500 text-amber-950 text-[10px] font-black px-4 py-1.5 rounded-bl-xl uppercase tracking-widest">
            Most Popular
          </div>
          <h3 className="text-xl font-bold text-amber-400 mb-2 flex items-center gap-2">
            Elite Organizer <Zap className="w-5 h-5 fill-amber-400" />
          </h3>
          <div className="flex items-end gap-1 mb-6">
            <span className="text-4xl font-black text-white">$24.99</span>
            <span className="text-gray-400 mb-1 font-bold">/mo</span>
          </div>
          <ul className="space-y-4 mb-8 flex-1">
            {['Unlimited Active Leagues', 'Live Match Streaming', 'Deep Analytics Dashboard', 'Gold Organizer Badge', 'Priority 24/7 Support'].map((feature, i) => (
              <li key={i} className="flex items-center gap-3 text-sm text-gray-300 font-medium">
                <Check className="w-5 h-5 text-amber-400" /> {feature}
              </li>
            ))}
          </ul>
          <button 
            onClick={() => handleUpgrade('elite')} 
            disabled={loading || !scriptLoaded}
            className="w-full py-3.5 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-400 hover:to-amber-500 text-amber-950 font-black rounded-xl transition-all shadow-lg shadow-amber-500/20 flex justify-center items-center gap-2"
          >
            {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Get Elite'}
          </button>
        </div>

      </div>
    </div>
  );
}
