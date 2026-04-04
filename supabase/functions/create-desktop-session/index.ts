import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function randomId(length = 32) {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let out = "";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  for (let i = 0; i < length; i++) {
    out += chars[bytes[i] % chars.length];
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
    const serviceRoleKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "missing_supabase_env" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const sessionId = randomId(24);
    const sessionSecret = randomId(48);
    const now = Date.now();
    const expiresAtMs = now + 10 * 60 * 1000;

    const qrPayload =
      `eleaguehub://desktop-link?sessionId=${encodeURIComponent(sessionId)}&sessionSecret=${encodeURIComponent(sessionSecret)}`;

    const { error } = await supabase
      .from("desktop_sessions")
      .insert({
        session_id: sessionId,
        session_secret: sessionSecret,
        status: "pending",
        qr_payload: qrPayload,
        created_at_ms: now,
        expires_at_ms: expiresAtMs,
        approved_at_ms: null,
        consumed_at_ms: null,
        paired_user_uid: null,
        paired_user_name: null,
        paired_user_email: null,
      });

    if (error) {
      return json({
        error: "create_failed",
        details: error.message,
      }, 500);
    }

    return json({
      session_id: sessionId,
      session_secret: sessionSecret,
      qr_payload: qrPayload,
      status: "pending",
      expires_at_ms: expiresAtMs,
    });
  } catch (e) {
    return json({
      error: "unexpected_error",
      details: String(e),
    }, 500);
  }
});
