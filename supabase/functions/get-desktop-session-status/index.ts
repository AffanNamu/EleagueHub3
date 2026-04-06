import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5.9.6';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Content-Type': 'application/json',
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

function errorResponse(
  message: string,
  status = 400,
  extra: Record<string, unknown> = {},
) {
  return jsonResponse(
    { success: false, message, error: message, ...extra },
    status,
  );
}

async function mintFirebaseCustomToken(uid: string): Promise<string> {
  const clientEmail = (Deno.env.get('FIREBASE_CLIENT_EMAIL') ?? '').trim();
  const privateKeyRaw = (Deno.env.get('FIREBASE_PRIVATE_KEY') ?? '').trim();

  if (!clientEmail || !privateKeyRaw) {
    throw new Error(
      'Missing FIREBASE_CLIENT_EMAIL or FIREBASE_PRIVATE_KEY secret',
    );
  }

  const privateKey = privateKeyRaw.replaceAll('\\n', '\n');
  const now = Math.floor(Date.now() / 1000);

  const key = await importPKCS8(privateKey, 'RS256');

  return await new SignJWT({
    uid,
    claims: { desktopLinked: true },
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience(
      'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    )
    .setIssuedAt(now)
    .setExpirationTime(now + 60 * 60)
    .sign(key);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceRoleKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return errorResponse(
      'Missing Supabase server environment variables',
      500,
      { status: 'failed', approved: false },
    );
  }

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch (_) {
    return errorResponse('Invalid JSON body', 400, {
      status: 'failed',
      approved: false,
    });
  }

  const sessionId = String(
    body['session_id'] ?? body['sessionId'] ?? '',
  ).trim();
  const sessionSecret = String(
    body['session_secret'] ?? body['sessionSecret'] ?? '',
  ).trim();

  if (!sessionId || !sessionSecret) {
    return errorResponse('Missing session_id/session_secret', 400, {
      status: 'failed',
      approved: false,
    });
  }

  const { data, error } = await supabase
    .from('desktop_sessions')
    .select('*')
    .eq('session_id', sessionId)
    .maybeSingle();

  if (error) {
    return errorResponse(`Failed to load session: ${error.message}`, 500, {
      status: 'failed',
      approved: false,
    });
  }

  if (!data) {
    return errorResponse('Desktop session not found', 404, {
      status: 'not_found',
      approved: false,
    });
  }

  if (String(data['session_secret'] ?? '') !== sessionSecret) {
    return errorResponse('Invalid desktop session secret', 401, {
      status: 'failed',
      approved: false,
    });
  }

  let currentStatus = String(data['status'] ?? 'pending').trim();
  const nowMs = Date.now();
  const expiresAtMs = Number(data['expires_at_ms'] ?? 0);

  if (
    expiresAtMs > 0 &&
    nowMs >= expiresAtMs &&
    currentStatus !== 'expired' &&
    currentStatus !== 'rejected' &&
    currentStatus !== 'consumed'
  ) {
    currentStatus = 'expired';
    await supabase
      .from('desktop_sessions')
      .update({ status: 'expired' })
      .eq('session_id', sessionId);
  }

  // ── try to mint custom token - but DON'T fail if it errors ───────────────
  let firebaseCustomToken = '';
  let customTokenError = '';

  if (currentStatus === 'approved') {
    const pairedUserUid = String(data['paired_user_uid'] ?? '').trim();

    if (pairedUserUid) {
      try {
        firebaseCustomToken = await mintFirebaseCustomToken(pairedUserUid);

        // Only mark consumed if we successfully minted the token
        const consumedAtMs = nowMs;
        await supabase
          .from('desktop_sessions')
          .update({ status: 'consumed', consumed_at_ms: consumedAtMs })
          .eq('session_id', sessionId);

        currentStatus = 'consumed';
      } catch (mintErr) {
        // Token minting failed - log error but still return approved
        // The web app will open without Firebase sign-in
        customTokenError = String(mintErr);
        console.error('Custom token mint failed:', mintErr);
      }
    }
  }

  const approved =
    currentStatus === 'approved' || currentStatus === 'consumed';

  return jsonResponse({
    success: true,
    status: currentStatus,
    approved,

    sessionId,
    expiresAtMs,

    pairedUserUid: String(data['paired_user_uid'] ?? ''),
    pairedUserName: String(data['paired_user_name'] ?? ''),
    pairedUserEmail: String(data['paired_user_email'] ?? ''),

    // Empty string if minting failed - web app handles this gracefully
    firebaseCustomToken,
    customTokenError,

    session_id: sessionId,
    expires_at_ms: expiresAtMs,
    paired_user_uid: String(data['paired_user_uid'] ?? ''),
    paired_user_name: String(data['paired_user_name'] ?? ''),
    paired_user_email: String(data['paired_user_email'] ?? ''),
    firebase_custom_token: firebaseCustomToken,
  });
});
