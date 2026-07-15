import { useState } from 'react';
import { doc, getDoc, updateDoc, setDoc, serverTimestamp, increment } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';

export function useCouponRedemption(leagueId: string) {
  const [redeeming, setRedeeming] = useState(false);
  const [error, setError] = useState('');

  const redeemCoupon = async (code: string) => {
    if (!auth.currentUser) throw new Error("Must be logged in.");
    if (code.trim().length < 6) throw new Error("Invalid coupon code.");
    
    setRedeeming(true);
    setError('');
    
    try {
      const cleanCode = code.trim().toUpperCase();
      const couponRef = doc(db, 'coupons', cleanCode);
      const couponSnap = await getDoc(couponRef);
      
      if (!couponSnap.exists()) {
        throw new Error("Coupon code does not exist.");
      }
      
      const data = couponSnap.data();
      if (!data.active) throw new Error("This coupon is no longer active.");
      if (data.leagueId && data.leagueId !== leagueId) throw new Error("Coupon is not valid for this league.");
      if (data.maxUses > 0 && data.currentUses >= data.maxUses) throw new Error("Coupon usage limit reached.");
      
      // Update coupon uses
      await updateDoc(couponRef, {
        currentUses: increment(1),
        lastUsedAt: serverTimestamp()
      });
      
      // Grant membership to the user (Maps to ensureDeterministicMembershipBestEffort)
      const membershipRef = doc(db, 'leagues', leagueId, 'memberships', auth.currentUser.uid);
      await setDoc(membershipRef, {
        userId: auth.currentUser.uid,
        role: 'participant', // Grants participant access
        redeemedCoupon: cleanCode,
        joinedAt: serverTimestamp()
      }, { merge: true });
      
      // Force page reload to re-evaluate the useLeagueAccess hook
      window.location.reload();
      
    } catch (err: any) {
      setError(err.message);
      setRedeeming(false);
    }
  };

  return { redeemCoupon, redeeming, error };
}
