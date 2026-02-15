import { AccessToken } from "livekit-server-sdk";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type, authorization",
  "access-control-max-age": "86400",
};

function jsonResponse(obj, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json",
      ...extraHeaders,
    },
  });
}

function textResponse(text, status = 200, extraHeaders = {}) {
  return new Response(text, {
    status,
    headers: {
      ...CORS_HEADERS,
      ...extraHeaders,
    },
  });
}

function sanitizeRoomTokenPart(s) {
  return String(s || "")
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_\-:.]/g, "_")
    .slice(0, 180);
}

function resolveRoomName(body) {
  const explicitRoomName = sanitizeRoomTokenPart(body.roomName);
  if (explicitRoomName) return explicitRoomName;

  // New: callId -> call_<8digits> (or any sanitized token part)
  const callId = sanitizeRoomTokenPart(body.callId);
  if (callId) return `call_${callId}`;

  const matchId = sanitizeRoomTokenPart(body.matchId);
  if (matchId) return `match_${matchId}`;

  const leagueId = sanitizeRoomTokenPart(body.leagueId);
  if (leagueId) return `league_${leagueId}`;

  return "";
}

function toHttpBaseUrl(livekitUrl) {
  const u = String(livekitUrl || "").trim();
  if (!u) return "";

  if (u.startsWith("wss://")) return "https://" + u.slice("wss://".length);
  if (u.startsWith("ws://")) return "http://" + u.slice("ws://".length);

  if (u.startsWith("https://") || u.startsWith("http://")) return u;

  return `https://${u}`;
}

async function makeAdminJwt(env, roomName) {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: "worker-admin",
    ttl: "5m",
  });

  at.addGrant({
    room: roomName,
    roomAdmin: true,
  });

  return at.toJwt();
}

async function mutePublishedTrack(env, roomName, identity, muted) {
  const adminJwt = await makeAdminJwt(env, roomName);
  const httpBase = toHttpBaseUrl(env.LIVEKIT_URL);

  const res = await fetch(
    `${httpBase}/twirp/livekit.RoomService/MutePublishedTrack`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${adminJwt}`,
      },
      body: JSON.stringify({
        room: roomName,
        identity,
        muted,
      }),
    }
  );

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`MutePublishedTrack failed ${res.status}: ${txt}`);
  }

  return res.json();
}

function kindFrom(body, roomName) {
  const rn = String(roomName || "").toLowerCase();
  if (sanitizeRoomTokenPart(body.callId)) return "call";
  if (rn.startsWith("call_")) return "call";
  if (sanitizeRoomTokenPart(body.matchId)) return "match";
  if (rn.startsWith("match_")) return "match";
  if (sanitizeRoomTokenPart(body.leagueId)) return "league";
  if (rn.startsWith("league_")) return "league";
  return "unknown";
}

// ============================================================================
// Firebase ID token verification (Cloudinary signed upload endpoint security)
// - Validates Authorization: Bearer <FIREBASE_ID_TOKEN>
// - Uses Google's public keys (cached) to verify RS256 signature
// - Requires env.FIREBASE_PROJECT_ID
// ============================================================================

let _firebaseCertCache = {
  keysByKid: new Map(),
  expiresAtMs: 0,
};

function _b64UrlToUint8Array(b64url) {
  const s = String(b64url || "")
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(String(b64url || "").length / 4) * 4, "=");
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function _pemToDerBytes(pem) {
  const lines = String(pem || "")
    .trim()
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("-----"));
  const b64 = lines.join("");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function _parseCacheControlMaxAgeSeconds(h) {
  const v = String(h || "");
  const m = v.match(/max-age=(\d+)/i);
  return m ? parseInt(m[1], 10) : 0;
}

async function _loadFirebaseCerts() {
  const now = Date.now();
  if (_firebaseCertCache.keysByKid.size > 0 && now < _firebaseCertCache.expiresAtMs) {
    return _firebaseCertCache.keysByKid;
  }

  const res = await fetch(
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com",
    { method: "GET" }
  );

  if (!res.ok) {
    throw new Error(`Failed to fetch Firebase certs: ${res.status}`);
  }

  const maxAge = _parseCacheControlMaxAgeSeconds(res.headers.get("cache-control"));
  const json = await res.json();

  const map = new Map();
  for (const [kid, pem] of Object.entries(json || {})) {
    map.set(kid, pem);
  }

  _firebaseCertCache = {
    keysByKid: map,
    expiresAtMs: now + Math.max(60, maxAge) * 1000,
  };

  return map;
}

function _decodeJwtParts(token) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) throw new Error("Invalid JWT format");

  const header = JSON.parse(new TextDecoder().decode(_b64UrlToUint8Array(parts[0])));
  const payload = JSON.parse(new TextDecoder().decode(_b64UrlToUint8Array(parts[1])));
  const signature = _b64UrlToUint8Array(parts[2]);

  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);

  return { header, payload, signature, signingInput };
}

async function _verifyFirebaseIdToken(env, request) {
  const projectId = String(env.FIREBASE_PROJECT_ID || "").trim();
  if (!projectId) {
    throw new Error("Worker missing FIREBASE_PROJECT_ID env var");
  }

  const auth = request.headers.get("authorization") || request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    return { ok: false, status: 401, error: "Missing Authorization: Bearer <Firebase ID token>" };
  }

  const token = m[1].trim();
  if (!token) {
    return { ok: false, status: 401, error: "Empty bearer token" };
  }

  let decoded;
  try {
    decoded = _decodeJwtParts(token);
  } catch (e) {
    return { ok: false, status: 401, error: "Invalid token (decode failed)" };
  }

  const { header, payload, signature, signingInput } = decoded;

  const kid = header && header.kid ? String(header.kid) : "";
  const alg = header && header.alg ? String(header.alg) : "";

  if (!kid || alg !== "RS256") {
    return { ok: false, status: 401, error: "Invalid token header" };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const iss = `https://securetoken.google.com/${projectId}`;

  if (payload.aud !== projectId) {
    return { ok: false, status: 401, error: "Invalid token audience" };
  }
  if (payload.iss !== iss) {
    return { ok: false, status: 401, error: "Invalid token issuer" };
  }
  if (!payload.sub || typeof payload.sub !== "string") {
    return { ok: false, status: 401, error: "Invalid token subject" };
  }
  if (payload.exp && typeof payload.exp === "number" && payload.exp < nowSec) {
    return { ok: false, status: 401, error: "Token expired" };
  }
  if (payload.iat && typeof payload.iat === "number" && payload.iat > nowSec + 60) {
    return { ok: false, status: 401, error: "Token issued in the future" };
  }

  let pem;
  try {
    const certs = await _loadFirebaseCerts();
    pem = certs.get(kid);
  } catch (e) {
    return { ok: false, status: 503, error: "Unable to load Firebase public keys" };
  }

  if (!pem) {
    return { ok: false, status: 401, error: "Unknown key id (kid)" };
  }

  let key;
  try {
    key = await crypto.subtle.importKey(
      "spki",
      _pemToDerBytes(pem),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );
  } catch (e) {
    return { ok: false, status: 500, error: "Failed to import public key" };
  }

  let valid = false;
  try {
    valid = await crypto.subtle.verify(
      { name: "RSASSA-PKCS1-v1_5" },
      key,
      signature,
      signingInput
    );
  } catch (_) {
    valid = false;
  }

  if (!valid) {
    return { ok: false, status: 401, error: "Invalid token signature" };
  }

  return {
    ok: true,
    status: 200,
    uid: payload.sub,
    email: typeof payload.email === "string" ? payload.email : null,
    payload,
  };
}

// ============================================================================
// Cloudinary signed upload helper
// - Signature: sha1(sorted_params + api_secret)
// - This endpoint returns signature + timestamp + public api_key
// - Requires env: CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
// ============================================================================

function _sanitizeCloudinaryPathPart(s) {
  return String(s || "")
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_\-\/:.]/g, "_")
    .replace(/\/{2,}/g, "/")
    .slice(0, 180);
}

function _sanitizeCloudinaryTagList(s) {
  // Cloudinary tags are comma-separated.
  return String(s || "")
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => t.replace(/[^a-zA-Z0-9_\-:.]/g, "_").slice(0, 40))
    .slice(0, 10)
    .join(",");
}

async function _sha1Hex(str) {
  const data = new TextEncoder().encode(String(str || ""));
  const digest = await crypto.subtle.digest("SHA-1", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const b of bytes) hex += b.toString(16).padStart(2, "0");
  return hex;
}

function _cloudinaryStringToSign(params) {
  // params: object of key -> value (string/number/bool). Exclude empty values.
  const entries = Object.entries(params)
    .filter(([k, v]) => v !== undefined && v !== null && String(v).trim() !== "")
    .map(([k, v]) => [String(k), String(v)]);

  entries.sort((a, b) => a[0].localeCompare(b[0]));

  // IMPORTANT: must be key=value joined by &
  return entries.map(([k, v]) => `${k}=${v}`).join("&");
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS } });
    }

    const url = new URL(request.url);

    // ---- ROUTE: POST /  -> issue token ----
    if (url.pathname === "/" && request.method === "POST") {
      if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
        return jsonResponse({ error: "Worker missing LiveKit env vars" }, 500);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const userId = (body.userId || "").toString().trim();
      const role = (body.role || "participant").toString().trim(); // "host" | "participant"
      const side = (body.side || "").toString().trim(); // optional: "home" | "away" | "unknown" | ...
      const roomName = resolveRoomName(body);

      if (!userId) {
        return jsonResponse({ error: "userId required" }, 400);
      }

      // Backward compatible:
      // - leagueId -> roomName: league_<leagueId>
      // - matchId  -> roomName: match_<matchId>
      // - callId   -> roomName: call_<callId>
      // - explicit roomName also supported
      if (!roomName) {
        return jsonResponse(
          { error: "One of leagueId, matchId, callId, or roomName is required" },
          400
        );
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const matchId = (body.matchId || "").toString().trim();
      const callId = (body.callId || "").toString().trim();

      const kind = kindFrom(body, roomName);

      const metadata = JSON.stringify({
        role: role || "participant",
        side: side || null,
        leagueId: leagueId || null,
        matchId: matchId || null,
        callId: callId || null,
        kind,
      });

      const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
        identity: userId,
        ttl: "2h",
        metadata,
      });

      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,
        canPublish: true,
        roomAdmin: role === "host",
      });

      const token = await at.toJwt();

      return jsonResponse({ token, url: env.LIVEKIT_URL, roomName, role, kind });
    }

    // ---- ROUTE: POST /admin  -> moderation helper (mute/unmute only) ----
    if (url.pathname === "/admin" && request.method === "POST") {
      if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
        return jsonResponse({ error: "Worker missing LiveKit env vars" }, 500);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const action = (body.action || "").toString().trim(); // mute|unmute
      const targetUserId = (body.targetUserId || "").toString().trim();
      const roomName = resolveRoomName(body);

      if (!action || !targetUserId) {
        return jsonResponse({ error: "action, targetUserId required" }, 400);
      }

      if (!roomName) {
        return jsonResponse(
          { error: "One of leagueId, matchId, callId, or roomName is required" },
          400
        );
      }

      try {
        if (action === "mute") {
          const out = await mutePublishedTrack(
            env,
            roomName,
            targetUserId,
            true
          );
          return jsonResponse({ ok: true, action, out });
        }

        if (action === "unmute") {
          const out = await mutePublishedTrack(
            env,
            roomName,
            targetUserId,
            false
          );
          return jsonResponse({ ok: true, action, out });
        }

        return jsonResponse({ error: "Unsupported action" }, 400);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    // ---- ROUTE: POST /cloudinary/sign  -> signed upload signature for Cloudinary ----
    // Requires Authorization: Bearer <Firebase ID token>
    if (url.pathname === "/cloudinary/sign" && request.method === "POST") {
      // Verify Firebase user
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse({ error: verified.error }, verified.status || 401);
      }

      const cloudName = String(env.CLOUDINARY_CLOUD_NAME || "").trim();
      const apiKey = String(env.CLOUDINARY_API_KEY || "").trim();
      const apiSecret = String(env.CLOUDINARY_API_SECRET || "").trim();

      if (!cloudName || !apiKey || !apiSecret) {
        return jsonResponse({ error: "Worker missing Cloudinary env vars" }, 500);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const nowSec = Math.floor(Date.now() / 1000);

      // Allow client to request a signature for controlled params only.
      // Folder MUST be under eleaguehub/ to reduce abuse.
      const folder = _sanitizeCloudinaryPathPart(body.folder || "").replace(/^\/+/, "");
      if (!folder || !folder.startsWith("eleaguehub/")) {
        return jsonResponse({ error: "Invalid folder (must start with eleaguehub/)" }, 400);
      }

      // public_id is optional; Cloudinary can auto-generate if omitted.
      const publicId = _sanitizeCloudinaryPathPart(body.publicId || body.public_id || "").replace(/^\/+/, "");

      const tags = _sanitizeCloudinaryTagList(body.tags || "");

      // Optional transformation (string). Keep it short to avoid abuse.
      const transformation = String(body.transformation || "").trim().slice(0, 500);

      // Build params to sign
      const paramsToSign = {
        folder,
        ...(publicId ? { public_id: publicId } : {}),
        ...(tags ? { tags } : {}),
        ...(transformation ? { transformation } : {}),
        timestamp: nowSec,
      };

      const toSign = _cloudinaryStringToSign(paramsToSign);
      const signature = await _sha1Hex(`${toSign}${apiSecret}`);

      return jsonResponse({
        ok: true,
        uid: verified.uid,
        cloudName,
        apiKey,
        timestamp: nowSec,
        signature,
        uploadUrl: `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`,
        params: paramsToSign,
      });
    }

    return textResponse("Not found", 404);
  },
};
