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
    token,
  };
}

// ============================================================================
// Cloudinary signed upload helper
// - Signature: sha1(sorted_params + api_secret)
// - This endpoint returns signature + timestamp + public api_key
// - Requires env: CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
//
// SECURITY (highlights):
// - This endpoint now validates that the user is allowed to upload highlights by
//   reading Firestore as the user (using the same Firebase ID token).
// - Zero-budget strategy: no Admin SDK required; reads are authorized by your
//   Firestore security rules.
// ============================================================================

function _sanitizeCloudinaryPathPart(s) {
  return String(s || "")
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_\-\/:.]/g, "_")
    .replace(/\/{2,}/g, "/")
    .slice(0, 240);
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

function _firestoreApiBase(env) {
  const projectId = String(env.FIREBASE_PROJECT_ID || "").trim();
  if (!projectId) throw new Error("Worker missing FIREBASE_PROJECT_ID env var");
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

async function _firestoreGetDoc(env, idToken, path) {
  const url = `${_firestoreApiBase(env)}/${path.replace(/^\/+/, "")}`;
  const res = await fetch(url, {
    method: "GET",
    headers: {
      authorization: `Bearer ${idToken}`,
    },
  });

  if (res.status === 404) return { ok: false, status: 404, doc: null };
  if (!res.ok) {
    const txt = await res.text();
    return { ok: false, status: res.status, error: txt || `Firestore GET failed ${res.status}` };
  }

  const doc = await res.json();
  return { ok: true, status: 200, doc };
}

function _fsString(doc, field) {
  const v = doc && doc.fields && doc.fields[field];
  if (!v) return "";
  if (typeof v.stringValue === "string") return v.stringValue;
  return "";
}

function _fsBool(doc, field) {
  const v = doc && doc.fields && doc.fields[field];
  if (!v) return null;
  if (typeof v.booleanValue === "boolean") return v.booleanValue;
  return null;
}

function _parseMatchHighlightsFolder(folder) {
  // expected: match_highlights/{leagueId}/{matchId}/{teamId}
  const f = String(folder || "").trim().replace(/^\/+/, "");
  const parts = f.split("/").filter(Boolean);
  if (parts.length !== 4) return null;
  if (parts[0] !== "match_highlights") return null;
  return { leagueId: parts[1], matchId: parts[2], teamId: parts[3], folder: f };
}

// Best-effort in-memory rate limiter (resets on worker restart).
// Prevents basic signature spamming to protect free tier.
const _rate = {
  // key -> { count, resetAtMs }
  map: new Map(),
};
function _rateKey(uid, leagueId, matchId) {
  return `${uid}::${leagueId}::${matchId}`;
}
function _checkRate(uid, leagueId, matchId) {
  const now = Date.now();
  const key = _rateKey(uid, leagueId, matchId);
  const windowMs = 60 * 60 * 1000; // 1 hour
  const max = 6; // allow a few retries (compression/upload retries etc)

  const cur = _rate.map.get(key);
  if (!cur || now > cur.resetAtMs) {
    _rate.map.set(key, { count: 1, resetAtMs: now + windowMs });
    return { ok: true };
  }

  if (cur.count >= max) {
    return { ok: false, error: "Rate limit exceeded. Please try again later." };
  }

  cur.count += 1;
  _rate.map.set(key, cur);
  return { ok: true };
}

function _isSafeCloudinaryPublicIdLeaf(publicId) {
  const s = String(publicId || "").trim();
  if (!s) return false;
  if (s.includes("/")) return false;
  // Keep it strict: Firestore highlightId is usually URL-safe / alnum-ish.
  // Allow dash/underscore only.
  return /^[A-Za-z0-9_-]{6,200}$/.test(s);
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
          const out = await mutePublishedTrack(env, roomName, targetUserId, true);
          return jsonResponse({ ok: true, action, out });
        }

        if (action === "unmute") {
          const out = await mutePublishedTrack(env, roomName, targetUserId, false);
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

      // Support both payload shapes:
      // - { params: { folder, public_id, overwrite, timestamp } }
      // - { folder, public_id, overwrite, timestamp }
      const paramsIn = body && body.params && typeof body.params === "object" ? body.params : body;

      const folderRaw = _sanitizeCloudinaryPathPart(paramsIn.folder || "").replace(/^\/+/, "");
      const parsed = _parseMatchHighlightsFolder(folderRaw);

      // Only highlights are supported here (tight abuse control).
      if (!parsed) {
        return jsonResponse(
          { error: "Invalid folder. Expected match_highlights/{leagueId}/{matchId}/{teamId}" },
          400
        );
      }

      const publicId = _sanitizeCloudinaryPathPart(paramsIn.public_id || paramsIn.publicId || "").replace(/^\/+/, "");
      if (!_isSafeCloudinaryPublicIdLeaf(publicId)) {
        return jsonResponse({ error: "Invalid public_id" }, 400);
      }

      // Enforce overwrite and block any extra transformation/tag usage (cost control).
      const overwrite = paramsIn.overwrite === true || String(paramsIn.overwrite).toLowerCase() === "true";
      if (!overwrite) {
        return jsonResponse({ error: "overwrite must be true" }, 400);
      }
      if (paramsIn.transformation || paramsIn.tags || paramsIn.eager || paramsIn.streaming_profile) {
        return jsonResponse({ error: "Transformations/tags are not allowed for highlights" }, 400);
      }

      // Rate limit per uid+match (best effort).
      const rl = _checkRate(verified.uid, parsed.leagueId, parsed.matchId);
      if (!rl.ok) {
        return jsonResponse({ error: rl.error }, 429);
      }

      // ---- Firestore authorization checks (zero-budget) ----
      // We read as the user using the same Firebase ID token. Reads are authorized by your Firestore rules.
      const membershipPath = `leagues/${parsed.leagueId}/memberships/${verified.uid}`;
      const matchPath = `leagues/${parsed.leagueId}/matches/${parsed.matchId}`;

      const memRes = await _firestoreGetDoc(env, verified.token, membershipPath);
      if (!memRes.ok) {
        return jsonResponse({ error: "Not allowed (membership not found)" }, 403);
      }

      const memTeamId = _fsString(memRes.doc, "teamId");
      if (!memTeamId || memTeamId !== parsed.teamId) {
        return jsonResponse({ error: "Not allowed (team mismatch)" }, 403);
      }

      const matchRes = await _firestoreGetDoc(env, verified.token, matchPath);
      if (!matchRes.ok) {
        return jsonResponse({ error: "Not allowed (match not found)" }, 403);
      }

      const isPlayed = _fsBool(matchRes.doc, "isPlayed");
      const status = _fsString(matchRes.doc, "status");
      const matchStatus = _fsString(matchRes.doc, "matchStatus");

      const finished = (isPlayed === true) || status === "FINISHED" || matchStatus === "FINISHED";
      if (!finished) {
        return jsonResponse({ error: "Not allowed (match not finished)" }, 403);
      }

      const homeTeamId = _fsString(matchRes.doc, "homeTeamId");
      const awayTeamId = _fsString(matchRes.doc, "awayTeamId");

      const isParticipant = (memTeamId === homeTeamId) || (memTeamId === awayTeamId);
      if (!isParticipant) {
        return jsonResponse({ error: "Not allowed (team did not participate)" }, 403);
      }

      // Use server timestamp (do not trust client time).
      const nowSec = Math.floor(Date.now() / 1000);

      // Build params to sign (minimal set).
      const paramsToSign = {
        folder: parsed.folder,
        public_id: publicId,
        overwrite: "true",
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

        // FYI only; client can ignore.
        uploadUrl: `https://api.cloudinary.com/v1_1/${cloudName}/video/upload`,
        params: paramsToSign,
      });
    }

    return textResponse("Not found", 404);
  },
};
