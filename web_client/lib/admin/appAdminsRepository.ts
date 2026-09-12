// lib/admin/appAdminsRepository.ts
//
// Mirrors lib/core/services/app_admins_service.dart's AppAdminsService:
// pricing-admin gating driven by a hardcoded super-admin UID OR membership
// in app/admins's `pricingAdmins` array field. Firestore rules (isPricingAdmin())
// enforce the same two-part check server-side — this is only for gating the UI.

import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

const STATIC_PRICING_ADMINS = new Set<string>(['QhYeBpvAoRV6j0xGigHkBth4qIG3']);

function looksLikeFirebaseUid(s: string): boolean {
  return s.trim().length > 20;
}

export async function isPricingAdminUid(uid: string | null | undefined): Promise<boolean> {
  const u = (uid ?? '').trim();
  if (!u || !looksLikeFirebaseUid(u)) return false;
  if (STATIC_PRICING_ADMINS.has(u)) return true;

  try {
    const snap = await getDoc(doc(db, 'app', 'admins'));
    if (!snap.exists()) return false;
    const list = snap.data()?.pricingAdmins;
    if (!Array.isArray(list)) return false;
    return list.some((v) => typeof v === 'string' && v.trim() === u);
  } catch (e) {
    console.warn('[appAdminsRepository] isPricingAdminUid check failed:', e);
    return false;
  }
}
