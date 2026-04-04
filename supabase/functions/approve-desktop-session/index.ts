import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  decodeProtectedHeader,
  importX509,
  jwtVerify,
} from "npm:jose@5.2.4";
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

let certCache: { atMs: number; keys: Record<string, string> } | null = null;

async function getFirebaseCerts(): Promise<Record<string, string>> {
  const now = Date.now();
  if (certCache && now - certCache.atMs < 60_000) return certCache.keys;

  const resp = await fetch(
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com",
  );
  if (!resp.ok) throw new Error(`certs_fetch_failed:${resp.status}`);
  const keys = (await resp.json()) as Record<string, string>;
  certCache = { atMs: now, keys };
  return keys;
}

async function verifyFirebaseIdToken(idToken: string) {
  const projectId = requireEnv("FIREBASE_PROJECT_ID");
  const issuer = `https://securetoken.google.com/${projectId}`;

  const header = decodeProtectedHeader(idToken);
  const kid = (header.kid ?? "").toString().trim();
  if (!kid) throw new Error("missing_kid");

  const certs = await getFirebaseCerts();
  const cert = certs[kid];
  if (!cert) throw new Error("kid_not_found");

  const key = await importX509(cert, "RS256");
  const { payload } = await jwtVerify(idToken, key, {
    issuer,
    audience: projectId,
  });

  const uid = (payload.user_id ?? payload.sub ?? "").toString().trim();
  if (!uid) throw new Error("missing_uid");

  const email = (payload.email ?? "").toString().trim();
  const name = (payload.name ?? payload.display_name ?? "").toString().trim();

  return { uid, email, name, payload };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const auth = (req.headers.get("authorization") ?? "").trim();
    const idToken = auth.toLowerCase().startsWith("bearer ")
      ? auth.substring(7).trim()
      : "";

    if (!idToken) {
      return json({
        success: false,
        status: "failed",
        message: "Missing authorization token.",
      }, 401);
    }

    const verified = await verifyFirebaseIdToken(idToken);

    const body = await req.json().catch(() => ({}));

    const sessionId = String(body.session_id ?? "").trim();
    const sessionSecret = String(body.session_secret ?? "").trim();
    const pairedUserNameFromBody = String(body.paired_user_name ?? "").trim();
    const pairedUserEmailFromBody = String(body.paired_user_email ?? "").trim();

    if (!sessionId || !sessionSecret) {
      return json({
        success: false,
        status: "failed",
        message: "Missing required fields.",
      }, 400);
    }

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: found, error: findError } = await supabase
      .from("desktop_sessions")
      .select("*")
      .eq("session_id", sessionId)
      .eq("session_secret", sessionSecret)
      .maybeSingle();

    if (findError) {
      return json({
        success: false,
        status: "failed",
        message: findError.message,
      }, 500);
    }

    if (!found) {
      return json({
        success: false,
        status: "failed",
        message: "Desktop session not found.",
      }, 404);
    }

    const now = Date.now();

    if (Number(found.expires_at_ms ?? 0) < now) {
      await supabase
        .from("desktop_sessions")
        .update({ status: "expired" })
        .eq("session_id", sessionId);

      return json({
        success: false,
        status: "expired",
        message: "Desktop session has expired.",
      }, 410);
    }

    const currentStatus = String(found.status ?? "").trim();

    if (currentStatus === "approved" || currentStatus === "consumed") {
      return json({
        success: true,
        status: currentStatus,
        message: "Desktop session already approved.",
      });
    }

    const safeName = pairedUserNameFromBody || verified.name;
    const safeEmail = pairedUserEmailFromBody || verified.email;

    const { error: updateError } = await supabase
      .from("desktop_sessions")
      .update({
        status: "approved",
        approved_at_ms: now,
        paired_user_uid: verified.uid,
        paired_user_name: safeName,
        paired_user_email: safeEmail,
      })
      .eq("session_id", sessionId)
      .eq("session_secret", sessionSecret);

    if (updateError) {
      return json({
        success: false,
        status: "failed",
        message: updateError.message,
      }, 500);
    }

    return json({
      success: true,
      status: "approved",
      message: "Desktop session approved successfully.",
      paired_user_uid: verified.uid,
      paired_user_name: safeName,
      paired_user_email: safeEmail,
    });
  } catch (e) {
    return json({
      success: false,
      status: "failed",
      message: String((e as Error)?.message ?? e),
    }, 500);
  }
});
