import { supabase } from '@/lib/supabaseClient';

export interface DesktopSession {
  sessionId: string;
  sessionSecret: string;
  qrPayload: string;
  expiresAtMs: number;
}

export interface DesktopSessionStatus {
  status: string;
  approved: boolean;
  pairedUserUid: string;
  pairedUserName: string;
  pairedUserEmail: string;
  firebaseCustomToken: string;
  customTokenError: string;
}

export async function createDesktopSession(): Promise<DesktopSession> {
  const { data, error } = await supabase.functions.invoke('create-session', {
    method: 'POST',
  });

  if (error) throw error;
  if (!data?.success) throw new Error(data?.message ?? 'Failed to create session');

  return {
    sessionId: data.sessionId,
    sessionSecret: data.sessionSecret,
    qrPayload: data.qrPayload,
    expiresAtMs: data.expiresAtMs,
  };
}

export async function getDesktopSessionStatus(
  sessionId: string,
  sessionSecret: string,
): Promise<DesktopSessionStatus> {
  const { data, error } = await supabase.functions.invoke('get-status', {
    body: { session_id: sessionId, session_secret: sessionSecret },
  });

  if (error) throw error;

  return {
    status: String(data?.status ?? 'failed'),
    approved: !!data?.approved,
    pairedUserUid: String(data?.pairedUserUid ?? ''),
    pairedUserName: String(data?.pairedUserName ?? ''),
    pairedUserEmail: String(data?.pairedUserEmail ?? ''),
    firebaseCustomToken: String(data?.firebaseCustomToken ?? ''),
    customTokenError: String(data?.customTokenError ?? ''),
  };
}
