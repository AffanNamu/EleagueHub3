import { useState } from 'react';
import { auth } from '@/lib/firebase';
import { PaymentsService } from '@/lib/services/paymentsService';
import { PaymentAttemptCreate } from '@/types/payment';

export function useWebCheckout() {
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState('');

  const initiateCheckout = async (paymentDetails: Omit<PaymentAttemptCreate, 'userId'>) => {
    if (!auth.currentUser) {
      setError('You must be logged in to make a payment.');
      return false;
    }

    setProcessing(true);
    setError('');

    try {
      const attemptId = await PaymentsService.createAttempt({
        ...paymentDetails,
        userId: auth.currentUser.uid,
      });

      // --- CROSSMINT GATEWAY INTEGRATION ---
      const response = await fetch('/api/crossmint/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: auth.currentUser.email,
          itemDetails: { name: paymentDetails.leagueName || "League Entry Fee" }
        }),
      });

      const result = await response.json();

      if (response.ok && result.success) {
        const txId = result.data?.id || `tx_cm_${Date.now()}`;
        const txRef = result.data?.reference || `ref_cm_${Date.now()}`;
        await PaymentsService.markClientSuccess(attemptId, txId, txRef);
        alert("Payment Successful! Your access has been granted via Crossmint.");
        return true;
      } else {
        await PaymentsService.markClientCancelled(attemptId, result.error || "Transaction failed.");
        throw new Error(result.error || "Payment failed to process.");
      }

    } catch (err: any) {
      console.error(err);
      setError(err.message || 'Payment failed.');
      return false;
    } finally {
      setProcessing(false);
    }
  };

  return { initiateCheckout, processing, error };
}
