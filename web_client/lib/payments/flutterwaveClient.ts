declare global {
  interface Window {
    FlutterwaveCheckout?: (config: Record<string, unknown>) => void;
  }
}

const SCRIPT_SRC = 'https://checkout.flutterwave.com/v3.js';
let scriptLoadPromise: Promise<void> | null = null;

function loadFlutterwaveScript(): Promise<void> {
  if (typeof window === 'undefined') {
    return Promise.reject(new Error('Flutterwave checkout can only run in the browser.'));
  }
  if (window.FlutterwaveCheckout) return Promise.resolve();
  if (scriptLoadPromise) return scriptLoadPromise;

  scriptLoadPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${SCRIPT_SRC}"]`);
    if (existing) {
      existing.addEventListener('load', () => resolve());
      existing.addEventListener('error', () => reject(new Error('Failed to load Flutterwave SDK.')));
      return;
    }
    const script = document.createElement('script');
    script.src = SCRIPT_SRC;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load Flutterwave SDK.'));
    document.head.appendChild(script);
  });

  return scriptLoadPromise;
}

export interface FlutterwaveChargeResult {
  success: boolean;
  cancelled: boolean;
  transactionId?: string;
  txRef?: string;
  status?: string;
  paymentMethod?: string;
}

export async function openFlutterwaveCheckout(params: {
  publicKey: string;
  txRef: string;
  amount: string;
  currency: string;
  redirectUrl: string;
  customerEmail: string;
  customerPhone: string;
  customerName: string;
  title: string;
  description: string;
  isTestMode: boolean;
}): Promise<FlutterwaveChargeResult> {
  await loadFlutterwaveScript();

  const paymentOptions =
    params.currency.toUpperCase() === 'NGN'
      ? 'card,ussd,banktransfer'
      : 'card,googlepay';

  return new Promise((resolve) => {
    let settled = false;

    window.FlutterwaveCheckout!({
      public_key: params.publicKey,
      tx_ref: params.txRef,
      amount: Number(params.amount),
      currency: params.currency,
      payment_options: paymentOptions,
      redirect_url: params.redirectUrl,
      customer: {
        email: params.customerEmail,
        phone_number: params.customerPhone,
        name: params.customerName,
      },
      customizations: {
        title: params.title,
        description: params.description,
      },
      meta: {
        environment: params.isTestMode ? 'test' : 'live',
      },
      callback: (response: Record<string, unknown>) => {
        settled = true;
        const status = String(response.status ?? '').toLowerCase();
        const successful = status === 'successful' || response.success === true;
        resolve({
          success: successful,
          cancelled: false,
          transactionId: response.transaction_id
            ? String(response.transaction_id)
            : response.id
              ? String(response.id)
              : undefined,
          txRef: response.tx_ref ? String(response.tx_ref) : params.txRef,
          status,
          paymentMethod: response.payment_type ? String(response.payment_type) : undefined,
        });
      },
      onclose: () => {
        if (!settled) {
          resolve({ success: false, cancelled: true });
        }
      },
    });
  });
}
