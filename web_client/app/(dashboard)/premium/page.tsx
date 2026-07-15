'use client';

import { Glass } from '@/components/ui/Glass';
import { Check, Crown, Zap } from 'lucide-react';

export default function PremiumScreen() {
  const handleUpgrade = () => {
    // Phase 14 will integrate Flutterwave / Payment Processor here
    alert("Payment integration (Flutterwave) initializing...");
  };

  return (
    <div className="space-y-8 pb-10">
      <div className="text-center max-w-2xl mx-auto pt-8">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-amber-500/10 border border-amber-500/30 mb-6">
          <Crown className="w-8 h-8 text-amber-500" />
        </div>
        <h1 className="text-3xl md:text-5xl font-black text-white tracking-tight mb-4">
          Unlock <span className="text-transparent bg-clip-text bg-gradient-to-r from-amber-400 to-amber-600">Elite</span> Power
        </h1>
        <p className="text-gray-400 text-lg">
          Take your leagues to the next level with advanced analytics, custom branding, and unlimited participants.
        </p>
      </div>

      <div className="flex flex-col md:flex-row gap-6 max-w-4xl mx-auto justify-center">
        
        {/* Pro Tier */}
        <Glass className="flex-1 p-8 border-t-4 border-t-[#38BDF8]">
          <h3 className="text-xl font-bold text-white mb-2">Pro Organizer</h3>
          <div className="flex items-end gap-1 mb-6">
            <span className="text-4xl font-black text-white">$9.99</span>
            <span className="text-gray-400 mb-1">/mo</span>
          </div>
          <ul className="space-y-4 mb-8">
            {['Up to 5 Active Leagues', 'Advanced Standings Engine', 'Basic Analytics', 'Standard Support'].map((feature, i) => (
              <li key={i} className="flex items-center gap-3 text-sm text-gray-300">
                <Check className="w-5 h-5 text-[#38BDF8]" /> {feature}
              </li>
            ))}
          </ul>
          <button onClick={handleUpgrade} className="w-full py-3 bg-brand-surface hover:bg-white/10 text-white font-bold rounded-xl border border-white/10 transition-colors">
            Get Pro
          </button>
        </Glass>

        {/* Elite Tier */}
        <Glass className="flex-1 p-8 border-t-4 border-t-amber-500 transform md:-translate-y-4 shadow-2xl shadow-amber-500/10 relative overflow-hidden">
          <div className="absolute top-0 right-0 bg-amber-500 text-black text-[10px] font-black px-3 py-1 rounded-bl-lg uppercase tracking-widest">
            Most Popular
          </div>
          <h3 className="text-xl font-bold text-amber-400 mb-2 flex items-center gap-2">
            Elite Organizer <Zap className="w-5 h-5" />
          </h3>
          <div className="flex items-end gap-1 mb-6">
            <span className="text-4xl font-black text-white">$24.99</span>
            <span className="text-gray-400 mb-1">/mo</span>
          </div>
          <ul className="space-y-4 mb-8">
            {['Unlimited Active Leagues', 'Live Match Streaming', 'Deep Analytics Dashboard', 'Verified Profile Badge', 'Priority 24/7 Support'].map((feature, i) => (
              <li key={i} className="flex items-center gap-3 text-sm text-gray-300">
                <Check className="w-5 h-5 text-amber-400" /> {feature}
              </li>
            ))}
          </ul>
          <button onClick={handleUpgrade} className="w-full py-3 bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-400 hover:to-amber-500 text-black font-black rounded-xl transition-colors shadow-lg shadow-amber-500/20">
            Get Elite
          </button>
        </Glass>

      </div>
    </div>
  );
}
