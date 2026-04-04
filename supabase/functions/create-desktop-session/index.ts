import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

function errorResponse(message: string, status = 400, extra: Record<string, unknown> = {}) {
  return jsonResponse(
    {
      success: false,
      message,
      error: message,
      ...extra,
    },
    status,
  );
}

function randomSecret(byteLength = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return errorResponse('Missing Supabase server environment variables', 500);
  }

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const sessionId = crypto.randomUUID();
  const sessionSecret = randomSecret(32);
  const createdAtMs = Date.now();
  const expiresAtMs = createdAtMs + 10 * 60 * 1000;

  const qrPayload =
    `eleaguehub://desktop-link` +
    `?sessionId=${encodeURIComponent(sessionId)}` +
    `&sessionSecret=${encodeURIComponent(sessionSecret)}`;

  const { error } = await supabase
    .from('desktop_sessions')
    .insert({
      session_id: sessionId,
      session_secret: sessionSecret,
      status: 'pending',
      qr_payload: qrPayload,
      created_at_ms: createdAtMs,
      expires_at_ms: expiresAtMs,
      paired_user_uid: null,
      paired_user_name: null,
      paired_user_email: null,
      approved_at_ms: null,
      consumed_at_ms: null,
    });

  if (error) {
    return errorResponse(`Failed to create session: ${error.message}`, 500);
  }

  return jsonResponse({
    success: true,

    sessionId,
    sessionSecret,
    qrPayload,
    createdAtMs,
    expiresAtMs,
    status: 'pending',
    approved: false,

    session_id: sessionId,
    session_secret: sessionSecret,
    qr_payload: qrPayload,
    created_at_ms: createdAtMs,
    expires_at_ms: expiresAtMs,
  });
});
