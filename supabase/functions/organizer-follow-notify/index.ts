// Supabase Edge Function: organizer-follow-notify
// Purpose: Receive Firebase ID token from client, validate it, then send FCM push (HTTP v1)
// to every follower of an organizer workspace when the organizer posts an
// update (announcement, new competition, verification change, ...).
//
// Unlike private-chat-notify/follow-notify (exactly one recipient), this
// broadcasts to every follower of master_leagues/{masterLeagueId} (its
// followers subcollection), so it fetches that follower list first, then
// each follower's FCM tokens, then sends one FCM v1 message per token.
//
// This function did not previously exist even though the Dart client
// (SupabaseEdgeNotificationsService.notifyFollowedOrganizerUpdate) has
// been calling it for organizer announcements all along -- every call
// silently 404'd. This is the fix: organizer-post push has never
// actually worked in production until this function exists and deploys.

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

async function fetchFollowerIds(
  projectId: string,
  accessToken: string,
  masterLeagueId: string,
): Promise<string[]> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/` +
    `master_leagues/${encodeURIComponent(masterLeagueId)}/followers?pageSize=500`;

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (resp.status === 404) return [];
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`firestore_followers_fetch_failed:${resp.status}:${txt}`);
  }

  const data = (await resp.json()) as {
    documents?: Array<{ name: string; fields?: Record<string, { stringValue?: string }> }>;
  };

  const ids = new Set<string>();
  for (const doc of data.documents ?? []) {
    const fromField = (doc.fields?.userId?.stringValue ?? "").trim();
    if (fromField) {
      ids.add(fromField);
      continue;
    }
    // Fall back to the doc's own id (the follower's uid) if userId is missing.
    const parts = doc.name.split("/");
    const docId = (parts[parts.length - 1] ?? "").trim();
    if (docId) ids.add(docId);
  }
  return Array.from(ids);
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
  if (!resp.ok) return [];

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
      masterLeagueId?: string;
      organizerName?: string;
      title?: string;
      message?: string;
      route?: string;
      eventType?: string;
      actorId?: string;
    };

    const masterLeagueId = (body.masterLeagueId ?? "").toString().trim();
    const organizerName = (body.organizerName ?? "An organizer").toString().trim() || "An organizer";
    const title = (body.title ?? "").toString().trim();
    const message = (body.message ?? "").toString().trim();
    const route = (body.route ?? "").toString().trim();
    const eventType = (body.eventType ?? "announcement").toString().trim() || "announcement";
    const actorId = (body.actorId ?? "").toString().trim();

    if (!masterLeagueId || !actorId) {
      return new Response(JSON.stringify({ error: "missing_fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Prevent spoofing -- only the actor themselves can trigger this.
    if (uid !== actorId) {
      return new Response(JSON.stringify({ error: "actor_mismatch" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = requireEnv("FIREBASE_PROJECT_ID");
    const accessToken = await getGoogleAccessToken();

    const followerIds = (await fetchFollowerIds(projectId, accessToken, masterLeagueId))
      .filter((id) => id !== actorId);

    if (followerIds.length === 0) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: "no_followers" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const notifTitle = eventType === "announcement" ? organizerName : title || organizerName;
    const notifBody = message || title || "Posted an update.";

    const buildMessage = (token: string) => ({
      message: {
        token,
        notification: {
          title: notifTitle,
          body: notifBody,
        },
        data: {
          type: "organizer_announcement",
          route,
          masterLeagueId,
          eventType,
          actorId,
          actorName: organizerName,
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "organizer_feed_channel",
            sound: "default",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      },
    });

    let sent = 0;
    const errors: string[] = [];

    // Fetch each follower's tokens and send in parallel across followers;
    // each follower may have multiple devices/tokens.
    await Promise.all(
      followerIds.map(async (followerId) => {
        let tokens: string[];
        try {
          tokens = await fetchRecipientTokens(projectId, accessToken, followerId);
        } catch (e) {
          errors.push(`tokens_fetch:${followerId}:${String((e as any)?.message ?? e)}`);
          return;
        }

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
              if (resp.status === 404 || txt.includes("UNREGISTERED")) {
                await deleteStaleToken(projectId, accessToken, followerId, token);
              } else {
                errors.push(`${resp.status}:${txt}`);
              }
            } catch (e) {
              errors.push(String((e as any)?.message ?? e));
            }
          }),
        );
      }),
    );

    return new Response(JSON.stringify({ ok: true, followers: followerIds.length, sent, errors }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String((e as any)?.message ?? e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
