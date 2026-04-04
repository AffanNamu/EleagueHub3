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

function requireEnv(name: string): string {
  const v = (Deno.env.get(name) ?? "").trim();
  if (!v) throw new Error(`missing_env:${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));

    const sessionId = String(body.session_id ?? "").trim();
    const sessionSecret = String(body.session_secret ?? "").trim();

    if (!sessionId || !sessionSecret) {
      return json({
        error: "missing_session_fields",
      }, 400);
    }

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: found, error } = await supabase
      .from("desktop_sessions")
      .select("*")
      .eq("session_id", sessionId)
      .eq("session_secret", sessionSecret)
      .maybeSingle();

    if (error) {
      return json({
        error: error.message,
      }, 500);
    }

    if (!found) {
      return json({
        session_id: sessionId,
        status: "not_found",
        approved: false,
        consumed: false,
        paired_user_uid: "",
        paired_user_name: "",
        paired_user_email: "",
      }, 404);
    }

    const now = Date.now();
    let status = String(found.status ?? "pending");

    if (Number(found.expires_at_ms ?? 0) < now && status === "pending") {
      status = "expired";

      await supabase
        .from("desktop_sessions")
        .update({ status: "expired" })
        .eq("session_id", sessionId)
        .eq("session_secret", sessionSecret);
    }

    return json({
      session_id: String(found.session_id ?? sessionId),
      status,
      approved: status === "approved" || status === "consumed",
      consumed: status === "consumed",
      paired_user_uid: String(found.paired_user_uid ?? ""),
      paired_user_name: String(found.paired_user_name ?? ""),
      paired_user_email: String(found.paired_user_email ?? ""),
    });
  } catch (e) {
    return json({
      error: String((e as Error)?.message ?? e),
    }, 500);
  }
});
