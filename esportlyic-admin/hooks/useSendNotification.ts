'use client';

import { useState } from 'react';
import type { NotificationSegment, SendNotificationResult } from '@/types/notification';

export function useSendNotification() {
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<SendNotificationResult | null>(null);

  async function send(params: {
    segment: NotificationSegment;
    leagueId?: string;
    title: string;
    body: string;
    postToHomeScreen: boolean;
  }) {
    setSubmitting(true);
    setError(null);
    setResult(null);

    try {
      const response = await fetch('/api/admin/notifications', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(params),
      });

      const responseBody = await response.json().catch(() => ({}));

      if (!response.ok) {
        setError(responseBody.error ?? 'Something went wrong.');
        setSubmitting(false);
        return;
      }

      setResult(responseBody.result);
      setSubmitting(false);
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
    }
  }

  return { send, submitting, error, result };
}
