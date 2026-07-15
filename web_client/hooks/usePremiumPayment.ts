import { useFlutterwave, closePaymentModal } from 'flutterwave-react-v3';
import { auth } from '@/lib/firebase';
import { useRouter } from 'next/navigation';

export function usePremiumPayment(plan: 'pro' | 'elite') {
  const router = useRouter();
  
  // Note: Your worker checks exact amounts based on pricing config in Firestore.
  // Make sure these match your Firestore pricing exactly.
  const amount = plan === 'elite' ? 24.99 : 9.99; 
  
  const config = {
    public_key: process.env.NEXT_PUBLIC_FLUTTERWAVE_PUBLIC_KEY || '',
    tx_ref: `tx_${auth.currentUser?.uid}_${Date.now()}`,
    amount: amount,
    currency: 'USD',
    payment_options: 'card,mobilemoney,ussd',
    customer: {
      email: auth.currentUser?.email || 'user@example.com',
      name: auth.currentUser?.displayName || 'User',
    },
    customizations: {
      title: `Upgrade to ${plan.toUpperCase()} Organizer`,
      description: 'Unlock premium league management tools',
      logo: 'https://your-logo-url.com/logo.png',
    },
  };

  const handleFlutterPayment = useFlutterwave(config);

  const triggerPayment = () => {
    if (!auth.currentUser) {
      alert("You must be logged in to upgrade.");
      return;
    }

    handleFlutterPayment({
      callback: async (response: any) => {
        if (response.status === "successful") {
          try {
            const idToken = await auth.currentUser!.getIdToken();
            const workerUrl = process.env.NEXT_PUBLIC_EDGE_WORKER_URL;
            
            // Securely verify and activate via your Cloudflare Worker
            const verifyRes = await fetch(`${workerUrl}/organizer-pro/activate`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${idToken}`
              },
              body: JSON.stringify({
                plan: plan,
                duration: '3mo', // Or pass dynamic duration based on UI
                provider: 'flutterwave',
                receiptId: `FLW-${response.transaction_id}`
              })
            });

            const data = await verifyRes.json();

            if (verifyRes.ok && data.success) {
              alert("Upgrade successful! Welcome to " + plan.toUpperCase());
              router.push('/master-leagues');
            } else {
              throw new Error(data.error || 'Backend verification failed');
            }
          } catch (error: any) {
            console.error("Verification Error:", error);
            alert("Payment succeeded, but activation failed: " + error.message);
          }
        } else {
          alert("Payment failed or was canceled.");
        }
        closePaymentModal(); 
      },
      onClose: () => {
        console.log("Payment modal closed");
      },
    });
  };

  return { triggerPayment };
}
