// Supabase Edge Function: private-chat-notify
// Purpose: Receive Firebase ID token from client, validate it, then send FCM push (HTTP v1)
// directly to the recipient's registered devices for a 1:1 DM.
//
// Unlike league/organizer/global chat (broadcast to a topic of subscribed
// devices), a private message has exactly one intended recipient, so there
// is no natural "topic" to use. Instead this reads that user's FCM tokens
// straight out of Firestore (users/{recipientId}/fcmTokens -- the same
// collection PushMessagingService._syncSpecificTokenToFirestore populates
// on every device, for every user, via the Firestore REST API) and sends
// one FCM v1 message per token. A token FCM reports as unregistered (the
// device uninstalled the app / token expired) is deleted from Firestore
// so it stops being tried on every future message.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  decodeProtectedHeader,
  importPKCS8,
  importX509,
  jwtVerify,
  SignJWT,
} from "npm:jose@5.2.4";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function requireEnv(name: string): string {
  const v = (Deno.env.get(name) ?? "").trim();
  if (!v) throw new Error(`missing_env:${name}`);
  return v;
}

// Cache Firebase certs for 60s to avoid fetching every request
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
  return { uid, payload };
}

// One access token, scoped for both sending FCM and reading Firestore via
// its REST API (no Admin SDK available in a Deno edge function).
async function getGoogleAccessToken(): Promise<string> {
  const clientEmail = requireEnv("FIREBASE_CLIENT_EMAIL");
  let privateKey = requireEnv("FIREBASE_PRIVATE_KEY");

  privateKey = privateKey.replace(/\\n/g, "\n");

  const pk = await importPKCS8(privateKey, "RS256");

  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope:
      "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(pk);

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
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

async function fetchRecipientTokens(
  projectId: string,
  accessToken: string,
  recipientId: string,
): Promise<string[]> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/` +
    `users/${encodeURIComponent(recipientId)}/fcmTokens?pageSize=100`;

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (resp.status === 404) return [];
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`firestore_tokens_fetch_failed:${resp.status}:${txt}`);
  }

  const data = (await resp.json()) as {
    documents?: Array<{ name: string; fields?: Record<string, { stringValue?: string }> }>;
  };

  const tokens = new Set<string>();
  for (const doc of data.documents ?? []) {
    const t = (doc.fields?.token?.stringValue ?? "").trim();
    if (t) tokens.add(t);
  }
  return Array.from(tokens);
}

async function deleteStaleToken(
  projectId: string,
  accessToken: string,
  recipientId: string,
  token: string,
): Promise<void> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/` +
    `users/${encodeURIComponent(recipientId)}/fcmTokens/${encodeURIComponent(token)}`;
  try {
    await fetch(url, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch (_) {
    // Best-effort cleanup only -- never fail the request over this.
  }
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
    const idToken = auth.toLowerCase().startsWith("bearer ")
      ? auth.substring(7).trim()
      : "";

    if (!idToken) {
      return new Response(JSON.stringify({ error: "missing_authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { uid } = await verifyFirebaseIdToken(idToken);

    const body = (await req.json()) as {
      threadId?: string;
      recipientId?: string;
      messageId?: string;
      senderId?: string;
      senderName?: string;
      preview?: string;
    };

    const threadId = (body.threadId ?? "").toString().trim();
    const recipientId = (body.recipientId ?? "").toString().trim();
    const messageId = (body.messageId ?? "").toString().trim();
    const senderId = (body.senderId ?? "").toString().trim();
    const senderName = (body.senderName ?? "Someone").toString().trim() || "Someone";
    const preview = (body.preview ?? "New message").toString().trim() || "New message";

    if (!threadId || !recipientId || !messageId || !senderId) {
      return new Response(JSON.stringify({ error: "missing_fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Prevent spoofing
    if (uid !== senderId) {
      return new Response(JSON.stringify({ error: "sender_mismatch" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // A sender can't be their own recipient (also guards against a
    // malformed/self thread id silently "succeeding" with no push sent).
    if (recipientId === senderId) {
      return new Response(JSON.stringify({ error: "invalid_recipient" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = requireEnv("FIREBASE_PROJECT_ID");
    const accessToken = await getGoogleAccessToken();

    const tokens = await fetchRecipientTokens(projectId, accessToken, recipientId);
    if (tokens.length === 0) {
      // Not an error -- the recipient simply has no registered device
      // (never opened notifications, or all tokens already expired).
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: "no_tokens" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const route = `/chat/${threadId}`;

    const buildMessage = (token: string) => ({
      message: {
        token,
        // NOTE: deliberately data-only (no top-level `notification` block)
        // -- see organizer-chat-notify's comment on this same shape for why.
        data: {
          type: "private_message",
          route,
          threadId,
          messageId,
          senderId,
          senderName,
          preview,
        },
        android: {
          priority: "high",
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: {
            aps: {
              sound: "default",
              alert: { title: senderName, body: preview },
            },
          },
        },
      },
    });

    let sent = 0;
    const errors: string[] = [];

    await Promise.all(
      tokens.map(async (token) => {
        try {
          const resp = await fetch(
            `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${accessToken}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify(buildMessage(token)),
            },
          );

          if (resp.ok) {
            sent += 1;
            return;
          }

          const txt = await resp.text();
          // FCM reports a dead token as NOT_FOUND / UNREGISTERED -- prune it
          // so future messages to this user don't keep retrying it.
          if (resp.status === 404 || txt.includes("UNREGISTERED")) {
            await deleteStaleToken(projectId, accessToken, recipientId, token);
          } else {
            errors.push(`${resp.status}:${txt}`);
          }
        } catch (e) {
          errors.push(String((e as any)?.message ?? e));
        }
      }),
    );

    return new Response(JSON.stringify({ ok: sent > 0, sent, errors }), {
      status: sent > 0 ? 200 : 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String((e as any)?.message ?? e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
