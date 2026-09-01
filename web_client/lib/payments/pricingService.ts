import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface RemotePricingConfig {
  currency: string;
  paymentsEnabled: boolean;
  flutterwaveEnabled: boolean;
  plans: Record<string, Record<string, number>>; // e.g. { pro: { '3mo': 5000, '6mo': 9000 } }
}

// Mimics RemotePricingService.dart
export async function getRemotePricingWeb(countryCode: string = 'US'): Promise<RemotePricingConfig | null> {
  // In Flutter, you fetch from `app/pricing`. 
  // You check localized docs, defaulting to 'en_US' or 'en_NG'. We'll fetch the global one for simplicity, 
  // but you can adjust the doc path if you use locale-specific documents like `app/pricing_NG`.
  const pricingDoc = await getDoc(doc(db, 'app', 'pricing'));
  
  if (!pricingDoc.exists()) return null;
  const data = pricingDoc.data();

  // Find the locale block (e.g., 'ng' for Nigeria, 'us' for US)
  const localeKey = countryCode.toLowerCase() === 'ng' ? 'en_ng' : 'en_us';
  const localeData = data[localeKey] || data['en_us'] || {};

  return {
    currency: localeData.currency || 'USD',
    paymentsEnabled: localeData.paymentsEnabled !== false,
    flutterwaveEnabled: localeData.flutterwaveEnabled !== false,
    plans: localeData.plans || {
      pro: { '3mo': 0, '6mo': 0, 'yearly': 0 },
      elite: { '3mo': 0, '6mo': 0, 'yearly': 0 }
    }
  };
}

export function getPlanPrice(config: RemotePricingConfig, planId: string, durationId: string): number {
  if (!config || !config.plans[planId]) return 0;
  return config.plans[planId][durationId] || 0;
}
