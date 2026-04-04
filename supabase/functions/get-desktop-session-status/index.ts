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
    return errorResponse('Missing Supabase server environment variables', 500, {
      status: 'failed',
      approved: false,
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const body = await req.json().catch(() => ({}));

  const sessionId = String(body.session_id ?? body.sessionId ?? '').trim();
  const sessionSecret = String(body.session_secret ?? body.sessionSecret ?? '').trim();

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

  if (String(data.session_secret ?? '') !== sessionSecret) {
    return errorResponse('Invalid desktop session secret', 401, {
      status: 'failed',
      approved: false,
    });
  }

  let currentStatus = String(data.status ?? 'pending');
  const nowMs = Date.now();
  const expiresAtMs = Number(data.expires_at_ms ?? 0);

  if (
    expiresAtMs > 0 &&
    nowMs >= expiresAtMs &&
    currentStatus !== 'consumed' &&
    currentStatus !== 'expired' &&
    currentStatus !== 'rejected'
  ) {
    currentStatus = 'expired';

    await supabase
      .from('desktop_sessions')
      .update({
        status: 'expired',
      })
      .eq('session_id', sessionId);
  }

  const approved = currentStatus === 'approved' || currentStatus === 'consumed';

  return jsonResponse({
    success: true,
    status: currentStatus,
    approved,

    sessionId,
    expiresAtMs,

    pairedUserUid: String(data.paired_user_uid ?? ''),
    pairedUserName: String(data.paired_user_name ?? ''),
    pairedUserEmail: String(data.paired_user_email ?? ''),

    session_id: sessionId,
    expires_at_ms: expiresAtMs,
    paired_user_uid: String(data.paired_user_uid ?? ''),
    paired_user_name: String(data.paired_user_name ?? ''),
    paired_user_email: String(data.paired_user_email ?? ''),
  });
});
