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

async function verifyFirebaseIdToken(idToken: string) {
  const apiKey = (Deno.env.get('FIREBASE_WEB_API_KEY') ?? '').trim();

  if (!apiKey) {
    throw new Error('Missing FIREBASE_WEB_API_KEY secret');
  }

  const resp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        idToken,
      }),
    },
  );

  const raw = await resp.text();
  let decoded: Record<string, unknown> = {};
  try {
    decoded = JSON.parse(raw);
  } catch (_) {}

  if (!resp.ok) {
    const errMap = decoded['error'];
    if (errMap && typeof errMap === 'object' && 'message' in errMap) {
      throw new Error(String((errMap as Record<string, unknown>)['message'] ?? 'Invalid Firebase token'));
    }
    throw new Error(`Firebase token lookup failed (HTTP ${resp.status})`);
  }

  const users = Array.isArray(decoded['users']) ? decoded['users'] as Array<Record<string, unknown>> : const [];
  if (users.isEmpty) {
    throw new Error('Firebase token lookup returned no user.');
  }

  const user = users.first;
  const uid = String(user['localId'] ?? '').trim();
  const email = String(user['email'] ?? '').trim();
  const name = String(user['displayName'] ?? '').trim();

  if (!uid) {
    throw new Error('Firebase token lookup returned empty uid.');
  }

  return {
    uid,
    email,
    name,
  };
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
    });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const bearerPrefix = 'Bearer ';
  const idToken = authHeader.startsWith(bearerPrefix)
    ? authHeader.slice(bearerPrefix.length).trim()
    : '';

  if (!idToken) {
    return errorResponse('Missing Authorization bearer token', 401, {
      status: 'failed',
    });
  }

  let firebaseUser: { uid: string; name: string; email: string };
  try {
    firebaseUser = await verifyFirebaseIdToken(idToken);
  } catch (e) {
    return errorResponse(`Invalid Firebase token: ${String(e)}`, 401, {
      status: 'failed',
    });
  }

  const body = await req.json().catch(() => ({}));

  const sessionId = String(body.session_id ?? body.sessionId ?? '').trim();
  const sessionSecret = String(body.session_secret ?? body.sessionSecret ?? '').trim();

  const pairedUserName = String(
    body.paired_user_name ??
      body.pairedUserName ??
      firebaseUser.name ??
      '',
  ).trim();

  const pairedUserEmail = String(
    body.paired_user_email ??
      body.pairedUserEmail ??
      firebaseUser.email ??
      '',
  ).trim();

  if (!sessionId || !sessionSecret) {
    return errorResponse('Missing session_id/session_secret', 400, {
      status: 'failed',
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { data, error } = await supabase
    .from('desktop_sessions')
    .select('*')
    .eq('session_id', sessionId)
    .maybeSingle();

  if (error) {
    return errorResponse(`Failed to load session: ${error.message}`, 500, {
      status: 'failed',
    });
  }

  if (!data) {
    return errorResponse('Desktop session not found', 404, {
      status: 'failed',
    });
  }

  if (String(data.session_secret ?? '') !== sessionSecret) {
    return errorResponse('Invalid desktop session secret', 401, {
      status: 'failed',
    });
  }

  const expiresAtMs = Number(data.expires_at_ms ?? 0);

  if (expiresAtMs > 0 && Date.now() >= expiresAtMs) {
    await supabase
      .from('desktop_sessions')
      .update({
        status: 'expired',
      })
      .eq('session_id', sessionId);

    return errorResponse('Desktop session expired', 400, {
      status: 'expired',
    });
  }

  const existingStatus = String(data.status ?? 'pending');

  if (existingStatus === 'approved' || existingStatus === 'consumed') {
    return jsonResponse({
      success: true,
      message: 'Desktop session already approved.',
      status: existingStatus,
      approved: true,

      pairedUserUid: String(data.paired_user_uid ?? firebaseUser.uid),
      pairedUserName: String(data.paired_user_name ?? pairedUserName),
      pairedUserEmail: String(data.paired_user_email ?? pairedUserEmail),

      paired_user_uid: String(data.paired_user_uid ?? firebaseUser.uid),
      paired_user_name: String(data.paired_user_name ?? pairedUserName),
      paired_user_email: String(data.paired_user_email ?? pairedUserEmail),
    });
  }

  if (existingStatus === 'expired' || existingStatus === 'rejected') {
    return errorResponse(`Desktop session is ${existingStatus}`, 400, {
      status: existingStatus,
    });
  }

  const approvedAtMs = Date.now();

  const { error: updateError } = await supabase
    .from('desktop_sessions')
    .update({
      status: 'approved',
      paired_user_uid: firebaseUser.uid,
      paired_user_name: pairedUserName,
      paired_user_email: pairedUserEmail,
      approved_at_ms: approvedAtMs,
    })
    .eq('session_id', sessionId);

  if (updateError) {
    return errorResponse(`Failed to approve session: ${updateError.message}`, 500, {
      status: 'failed',
    });
  }

  return jsonResponse({
    success: true,
    message: 'Desktop session approved.',
    status: 'approved',
    approved: true,

    pairedUserUid: firebaseUser.uid,
    pairedUserName,
    pairedUserEmail,
    approvedAtMs,

    paired_user_uid: firebaseUser.uid,
    paired_user_name: pairedUserName,
    paired_user_email: pairedUserEmail,
    approved_at_ms: approvedAtMs,
  });
});
