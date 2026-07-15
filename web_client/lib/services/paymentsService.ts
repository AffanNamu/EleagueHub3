import { collection, doc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { PaymentAttemptCreate, ClientRecordPaymentResult } from '@/types/payment';

export class PaymentsService {
  static async createAttempt(attempt: PaymentAttemptCreate): Promise<string> {
    if (!auth.currentUser) throw new Error('Not signed in.');
    if (attempt.userId !== auth.currentUser.uid) throw new Error('UID mismatch.');

    const attemptsCol = collection(db, 'payment_attempts');
    const ref = doc(attemptsCol);
    const nowMs = Date.now();

    const attemptData = {
      attemptId: ref.id,
      userId: attempt.userId,
      provider: attempt.provider,
      currency: attempt.currency,
      amount: attempt.amount,
      amountStr: attempt.amountStr,
      status: 'pending',
      productType: attempt.productType || '',
      productSubType: attempt.productSubType || '',
      leagueId: attempt.leagueId || '',
      leagueName: attempt.leagueName || '',
      masterLeagueId: attempt.masterLeagueId || '',
      planId: attempt.planId || '',
      planDurationId: attempt.planDurationId || '',
      couponCode: attempt.couponCode || '',
      items: attempt.items || [],
      metadata: attempt.metadata || {},
      createdAt: serverTimestamp(),
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    };

    await setDoc(ref, attemptData);
    return ref.id;
  }

  static async markClientSuccess(
    attemptId: string,
    txId: string,
    txRef: string
  ): Promise<ClientRecordPaymentResult> {
    if (!auth.currentUser || !attemptId) throw new Error("Invalid request");

    const nowMs = Date.now();
    const paymentId = `pay_${nowMs}_${Math.floor(Math.random() * 10000)}`;
    const receiptId = `rec_${txId.substring(0, 8) || nowMs}`;

    const attemptRef = doc(db, 'payment_attempts', attemptId);
    
    // In your Dart app, this writes to both `payments` and `payment_attempts` using a batch, 
    // but the backend webhook usually does the final verification.
    await updateDoc(attemptRef, {
      status: 'client_success',
      paymentId: paymentId,
      receiptId: receiptId,
      paidAtMs: nowMs,
      providerTransactionId: txId,
      txRef: txRef,
      updatedAtMs: nowMs,
    });

    return { paymentId, receiptId, paidAtMs: nowMs };
  }

  static async markClientCancelled(attemptId: string, reason: string) {
    if (!attemptId) return;
    await updateDoc(doc(db, 'payment_attempts', attemptId), {
      status: 'client_cancelled',
      errorMessage: reason,
      updatedAtMs: Date.now(),
    });
  }

  static async markClientFailed(attemptId: string, errorMessage: string) {
    if (!attemptId) return;
    await updateDoc(doc(db, 'payment_attempts', attemptId), {
      status: 'client_failed',
      errorMessage: errorMessage,
      updatedAtMs: Date.now(),
    });
  }
}
