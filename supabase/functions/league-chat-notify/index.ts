import { decodeProtectedHeader, importPKCS8, importX509, jwtVerify, SignJWT } from "npm:jose@5.2.4";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

let certCache: { atMs: number; keys: Record<string, string> } | null = null;

async function getFirebaseCerts(): Promise<Record<string, string>> {
  const now = Date.now();
  if (certCache && now - certCache.atMs < 60_000) return certCache.keys;

  const resp = await fetch("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com");
  if (!resp.ok) throw new Error(`certs_fetch_failed:${resp.status}`);
  const keys = (await resp.json()) as Record<string, string>;

  certCache = { atMs: now, keys };
  return keys;
}

function requireEnv(name: string): string {
  const v = (Deno.env.get(name) ?? "").trim();
  if (!v) throw new Error(`missing_env:${name}`);
  return v;
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

  return { uid, payload };
}

async function getGoogleAccessToken(): Promise<string> {
  const clientEmail = requireEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = requireEnv("FIREBASE_PRIVATE_KEY");
  privateKey = privateKey.replace(/\\n/g, "\n");

  const pk = await importPKCS8(privateKey, "RS256");

  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(pk);

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`token_exchange_failed:${resp.status}:${txt}`);
  }

  const data = (await resp.json()) as { access_token?: string };
  const token = (data.access_token ?? "").trim();
  if (!token) throw new Error("missing_access_token");
  return token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const auth = (req.headers.get("authorization") ?? "").trim();
    const idToken = auth.toLowerCase().startsWith("bearer ") ? auth.substring(7).trim() : "";
    if (!idToken) {
      return new Response(JSON.stringify({ error: "missing_authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { uid } = await verifyFirebaseIdToken(idToken);

    const body = (await req.json()) as {
      leagueId?: string;
      leagueName?: string;
      messageId?: string;
      senderId?: string;
      senderName?: string;
      preview?: string;
    };

    const leagueId = (body.leagueId ?? "").toString().trim();
    const leagueName = (body.leagueName ?? "League").toString().trim() || "League";
    const messageId = (body.messageId ?? "").toString().trim();
    const senderId = (body.senderId ?? "").toString().trim();
    const senderName = (body.senderName ?? "Someone").toString().trim() || "Someone";
    const preview = (body.preview ?? "New message").toString().trim() || "New message";

    if (!leagueId || !messageId || !senderId) {
      return new Response(JSON.stringify({ error: "missing_fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Ensure caller cannot spoof senderId
    if (uid !== senderId) {
      return new Response(JSON.stringify({ error: "sender_mismatch" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = requireEnv("FIREBASE_PROJECT_ID");
    const accessToken = await getGoogleAccessToken();

    const condition = `'league_${leagueId}' in topics && !('mute_${senderId}_${leagueId}' in topics)`;
    const route = `/leagues/${leagueId}/chat`;

    const fcmReq = {
      message: {
        condition,
        notification: {
          title: leagueName,
          body: `${senderName}: ${preview}`,
        },
        data: {
          type: "league_chat",
          route,
          leagueId,
          leagueName,
          messageId,
          senderId,
          senderName,
          preview,
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "league_chat_channel",
            sound: "default",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      },
    };

    const resp = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmReq),
    });

    if (!resp.ok) {
      const txt = await resp.text();
      return new Response(JSON.stringify({ ok: false, error: "fcm_send_failed", status: resp.status, body: txt }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const out = await resp.json();
    return new Response(JSON.stringify({ ok: true, result: out }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
