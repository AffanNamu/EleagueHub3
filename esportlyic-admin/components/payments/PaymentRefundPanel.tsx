'use client';

import { useState } from 'react';
import { usePaymentRefund } from '@/hooks/usePaymentRefund';
import { AUTO_REVOKABLE_PRODUCT_TYPES } from '@/types/payment';
import { formatRelativeTime } from '@/lib/utils';
import type { Payment } from '@/types/payment';

function isAutoRevokable(productType: string): boolean {
  return (AUTO_REVOKABLE_PRODUCT_TYPES as readonly string[]).includes(productType);
}

export function PaymentRefundPanel({ payment, canRefund }: { payment: Payment; canRefund: boolean }) {
  const { refund, submitting, error } = usePaymentRefund(payment.paymentId);
  const [reason, setReason] = useState('');
  const [revokeAccess, setRevokeAccess] = useState(true);
  const revocable = isAutoRevokable(payment.productType);

  if (payment.refundedAtMs) {
    return (
      <div className="panel p-5">
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Refund</h2>
        <div className="rounded-sm border border-signal-warning/40 bg-signal-warningFaint px-3 py-2 text-sm text-signal-warning">
          Marked refunded {formatRelativeTime(payment.refundedAtMs)}
          {payment.refundedByEmail ? ` by ${payment.refundedByEmail}` : ''}.
        </div>
        {payment.refundReason && (
          <p className="mt-2 text-sm text-ink-secondary">Reason: {payment.refundReason}</p>
        )}
      </div>
    );
  }

  if (!canRefund) return null;

  async function handleSubmit() {
    if (!reason.trim()) return;
    if (
      !confirm(
        'Mark this payment as refunded? This does not send money back through Flutterwave/App Store/Play Console — issue the actual refund there separately. This action cannot be undone here.',
      )
    ) {
      return;
    }
    await refund(reason, revokeAccess && revocable);
  }

  return (
    <div className="panel space-y-3 p-5">
      <h2 className="font-display text-sm font-semibold text-ink-primary">Refund</h2>

      <div className="rounded-sm border border-signal-warning/40 bg-signal-warningFaint px-3 py-2 text-xs text-signal-warning">
        This only records the refund here and, optionally, revokes the access it granted. It does
        not call Flutterwave, App Store, or Google Play — issue the actual money-back in that
        provider's dashboard separately.
      </div>

      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Reason</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={2}
          placeholder="Why is this payment being refunded?"
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        />
      </div>

      {revocable ? (
        <label className="flex items-center gap-2 text-sm text-ink-secondary">
          <input
            type="checkbox"
            checked={revokeAccess}
            onChange={(e) => setRevokeAccess(e.target.checked)}
            className="h-4 w-4 rounded-sm border-base-border accent-brand"
          />
          Also revoke the access this payment granted
        </label>
      ) : (
        <p className="text-xs text-ink-muted">
          No automatic access revocation is available for this product type ({payment.productType || 'unknown'}) —
          revoke access manually if needed.
        </p>
      )}

      <div className="flex justify-end pt-1">
        <button
          onClick={handleSubmit}
          disabled={submitting || !reason.trim()}
          className="rounded-sm bg-signal-danger px-4 py-2 text-sm font-medium text-white hover:opacity-90 disabled:opacity-60"
        >
          {submitting ? 'Marking refunded…' : 'Mark as refunded'}
        </button>
      </div>
    </div>
  );
}
