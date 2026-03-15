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

// ─────────────────────────────────────────────────────────────────────────────
// Firebase ID Token verification
// ─────────────────────────────────────────────────────────────────────────────

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

function _uint8ArrayToB64Url(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = "";
  for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function _utf8ToB64Url(s) {
  return _uint8ArrayToB64Url(new TextEncoder().encode(String(s || "")));
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
  if (
    _firebaseCertCache.keysByKid.size > 0 &&
    now < _firebaseCertCache.expiresAtMs
  ) {
    return _firebaseCertCache.keysByKid;
  }

  const res = await fetch(
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com",
    { method: "GET" }
  );

  if (!res.ok) {
    throw new Error(`Failed to fetch Firebase certs: ${res.status}`);
  }

  const maxAge = _parseCacheControlMaxAgeSeconds(
    res.headers.get("cache-control")
  );
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

  const header = JSON.parse(
    new TextDecoder().decode(_b64UrlToUint8Array(parts[0]))
  );
  const payload = JSON.parse(
    new TextDecoder().decode(_b64UrlToUint8Array(parts[1]))
  );
  const signature = _b64UrlToUint8Array(parts[2]);

  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);

  return { header, payload, signature, signingInput };
}

async function _verifyFirebaseIdToken(env, request) {
  const projectId = String(env.FIREBASE_PROJECT_ID || "").trim();
  if (!projectId) {
    throw new Error("Worker missing FIREBASE_PROJECT_ID env var");
  }

  const auth =
    request.headers.get("authorization") ||
    request.headers.get("Authorization") ||
    "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    return {
      ok: false,
      status: 401,
      error: "Missing Authorization: Bearer <Firebase ID token>",
    };
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
    return {
      ok: false,
      status: 503,
      error: "Unable to load Firebase public keys",
    };
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

// ─────────────────────────────────────────────────────────────────────────────
// Service Account helpers (for Custom Claims & Firestore REST writes)
// ─────────────────────────────────────────────────────────────────────────────

let _saSigningKeyCache = { key: null, forEmail: "" };
let _googleAccessTokenCache = { accessToken: "", expiresAtMs: 0 };

function _requireEnvString(env, key) {
  const v = String(env[key] || "").trim();
  if (!v) throw new Error(`Worker missing ${key} env var`);
  return v;
}

function _serviceAccountPrivateKeyPem(env) {
  const raw = String(env.FIREBASE_PRIVATE_KEY || "").trim();
  if (!raw) throw new Error("Worker missing FIREBASE_PRIVATE_KEY env var");
  return raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
}

async function _importServiceAccountSigningKey(env) {
  const email = _requireEnvString(env, "FIREBASE_CLIENT_EMAIL");
  if (_saSigningKeyCache.key && _saSigningKeyCache.forEmail === email) {
    return _saSigningKeyCache.key;
  }

  const pem = _serviceAccountPrivateKeyPem(env);
  const der = _pemToDerBytes(pem);

  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  _saSigningKeyCache = { key, forEmail: email };
  return key;
}

async function _signRs256(env, signingInputUtf8) {
  const key = await _importServiceAccountSigningKey(env);
  const data = new TextEncoder().encode(String(signingInputUtf8 || ""));
  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    data
  );
  return _uint8ArrayToB64Url(new Uint8Array(sig));
}

async function _serviceAccountAccessToken(env) {
  const now = Date.now();
  if (
    _googleAccessTokenCache.accessToken &&
    now + 15000 < _googleAccessTokenCache.expiresAtMs
  ) {
    return _googleAccessTokenCache.accessToken;
  }

  const tokenUri = String(
    env.FIREBASE_TOKEN_URI || "https://oauth2.googleapis.com/token"
  ).trim();
  const clientEmail = _requireEnvString(env, "FIREBASE_CLIENT_EMAIL");

  const iat = Math.floor(now / 1000);
  const exp = iat + 60 * 60;

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: tokenUri,
    iat,
    exp,
    scope:
      "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/datastore",
  };

  const encodedHeader = _utf8ToB64Url(JSON.stringify(header));
  const encodedPayload = _utf8ToB64Url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await _signRs256(env, signingInput);
  const assertion = `${signingInput}.${signature}`;

  const body = new URLSearchParams();
  body.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  body.set("assertion", assertion);

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(
      `Failed to fetch OAuth access token (${res.status}): ${txt}`
    );
  }

  const json = await res.json();
  const accessToken = String(json.access_token || "").trim();
  const expiresIn =
    typeof json.expires_in === "number" ? json.expires_in : 3600;

  if (!accessToken) {
    throw new Error("OAuth response missing access_token");
  }

  _googleAccessTokenCache = {
    accessToken,
    expiresAtMs: now + expiresIn * 1000,
  };

  return accessToken;
}

function _identityToolkitBase(env) {
  const projectId = _requireEnvString(env, "FIREBASE_PROJECT_ID");
  return `https://identitytoolkit.googleapis.com/v1/projects/${projectId}`;
}

function _claimsString(claimsObj) {
  return JSON.stringify(claimsObj || {});
}

async function _lookupExistingCustomClaims(env, uid) {
  const accessToken = await _serviceAccountAccessToken(env);

  const res = await fetch(`${_identityToolkitBase(env)}/accounts:lookup`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ localId: [String(uid || "").trim()] }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`accounts:lookup failed (${res.status}): ${txt}`);
  }

  const json = await res.json();
  const users = Array.isArray(json.users) ? json.users : [];
  if (users.length < 1) return {};

  const customAttributesStr =
    typeof users[0].customAttributes === "string"
      ? users[0].customAttributes
      : "";
  if (!customAttributesStr) return {};

  try {
    return JSON.parse(customAttributesStr);
  } catch (_) {
    return {};
  }
}

async function _setFirebaseCustomClaims(env, uid, claimsObj) {
  const accessToken = await _serviceAccountAccessToken(env);

  const res = await fetch(`${_identityToolkitBase(env)}/accounts:update`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      localId: String(uid || "").trim(),
      customAttributes: _claimsString(claimsObj),
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`accounts:update failed (${res.status}): ${txt}`);
  }

  return res.json();
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore REST API helpers (service-account scoped)
// ─────────────────────────────────────────────────────────────────────────────

function _firestoreRestBase(env) {
  const projectId = _requireEnvString(env, "FIREBASE_PROJECT_ID");
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

async function _firestorePatchDoc(env, docPath, fieldsObj) {
  const accessToken = await _serviceAccountAccessToken(env);
  const base = _firestoreRestBase(env);
  const cleanPath = String(docPath || "")
    .trim()
    .replace(/^\/+/, "");

  const updateMaskParams = Object.keys(fieldsObj)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join("&");

  const url = `${base}/${cleanPath}?${updateMaskParams}`;

  const firestoreFields = {};
  for (const [key, value] of Object.entries(fieldsObj)) {
    if (typeof value === "boolean") {
      firestoreFields[key] = { booleanValue: value };
    } else if (typeof value === "number" && Number.isInteger(value)) {
      firestoreFields[key] = { integerValue: String(value) };
    } else if (typeof value === "number") {
      firestoreFields[key] = { doubleValue: value };
    } else if (typeof value === "string") {
      firestoreFields[key] = { stringValue: value };
    } else if (value && typeof value === "object" && value._serverTimestamp) {
      firestoreFields[key] = {
        timestampValue: new Date().toISOString(),
      };
    }
  }

  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ fields: firestoreFields }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(
      `Firestore PATCH ${cleanPath} failed (${res.status}): ${txt}`
    );
  }

  return res.json();
}

async function _firestoreGetDocSA(env, docPath) {
  const accessToken = await _serviceAccountAccessToken(env);
  const base = _firestoreRestBase(env);
  const cleanPath = String(docPath || "")
    .trim()
    .replace(/^\/+/, "");

  const res = await fetch(`${base}/${cleanPath}`, {
    method: "GET",
    headers: {
      authorization: `Bearer ${accessToken}`,
    },
  });

  if (res.status === 404) return { ok: false, status: 404, doc: null };
  if (!res.ok) {
    const txt = await res.text();
    return {
      ok: false,
      status: res.status,
      error: txt || `Firestore GET failed ${res.status}`,
    };
  }

  const doc = await res.json();
  return { ok: true, status: 200, doc };
}

// ─────────────────────────────────────────────────────────────────────────────
// Flutterwave verification (shared)
// ─────────────────────────────────────────────────────────────────────────────

function _normalizePlan(planId) {
  const p = String(planId || "").trim().toLowerCase();
  if (p === "basic" || p === "pro" || p === "elite") return p;
  return "";
}

function _planOrder(planId) {
  const p = String(planId || "").trim().toLowerCase();
  if (p === "basic") return 1;
  if (p === "pro") return 2;
  if (p === "elite") return 3;
  return 0;
}

function _planFromTxRef(txRef) {
  const s = String(txRef || "").trim();
  const m = s.match(/^EH-MLK-([A-Z]+)-/);
  if (!m) return "";
  return _normalizePlan(String(m[1] || "").trim().toLowerCase());
}

function _uidFromTxRef(txRef) {
  const s = String(txRef || "").trim();
  const patterns = [
    /(?:^|-)UID-([A-Za-z0-9_-]{20,128})(?:-|$)/i,
    /(?:^|_)UID_([A-Za-z0-9_-]{20,128})(?:_|$)/i,
  ];

  for (const pattern of patterns) {
    const m = s.match(pattern);
    if (m && m[1]) return String(m[1]).trim();
  }
  return "";
}

function _extractFlutterwaveTxIdFromReceipt(receiptId) {
  const r = String(receiptId || "").trim();
  if (!r) return "";
  if (r.startsWith("FLW-") && r.length > 4) return r.slice(4).trim();
  return r;
}

async function _verifyFlutterwaveTransactionGeneric(env, transactionId) {
  const secret = _requireEnvString(env, "FLUTTERWAVE_SECRET_KEY");
  const txId = String(transactionId || "").trim();
  if (!txId) throw new Error("Missing flutterwave transactionId");

  const res = await fetch(
    `https://api.flutterwave.com/v3/transactions/${encodeURIComponent(
      txId
    )}/verify`,
    {
      method: "GET",
      headers: {
        authorization: `Bearer ${secret}`,
        "content-type": "application/json",
      },
    }
  );

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Flutterwave verify failed (${res.status}): ${txt}`);
  }

  const json = await res.json();

  const topStatus = String(json.status || "").trim().toLowerCase();
  const data = json.data || {};

  const paymentStatus = String(data.status || "").trim().toLowerCase();
  const txRef = String(data.tx_ref || "").trim();
  const currency = String(data.currency || "").trim().toUpperCase();
  const amount = typeof data.amount === "number" ? data.amount : null;

  const customer = data.customer || {};
  const customerEmail =
    typeof customer.email === "string" ? customer.email.trim() : "";

  const ok = topStatus === "success" && paymentStatus === "successful";

  return {
    ok,
    txId,
    txRef,
    currency,
    amount,
    customerEmail,
    paymentStatus,
    topStatus,
    raw: json,
  };
}

async function _verifyFlutterwaveTransaction(env, transactionId) {
  const result = await _verifyFlutterwaveTransactionGeneric(env, transactionId);

  if (!result.ok) {
    throw new Error(
      `Flutterwave transaction not successful (status=${result.topStatus}, data.status=${result.paymentStatus})`
    );
  }

  if (!result.txRef.startsWith("EH-MLK-")) {
    throw new Error("Flutterwave tx_ref is not a Master League purchase");
  }

  const planFromRef = _planFromTxRef(result.txRef);
  if (!planFromRef) {
    throw new Error("Unable to determine plan from tx_ref");
  }

  if (!result.currency || !["NGN", "USD"].includes(result.currency)) {
    throw new Error("Unsupported currency from Flutterwave verify");
  }

  if (result.amount == null || result.amount <= 0) {
    throw new Error("Invalid amount from Flutterwave verify");
  }

  return {
    ...result,
    planId: planFromRef,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Organizer Pro activation (existing)
// ─────────────────────────────────────────────────────────────────────────────

async function _activateOrganizerPro(env, verified, body) {
  const requestedPlan = _normalizePlan(body.plan);
  if (!requestedPlan) {
    return {
      ok: false,
      status: 400,
      error: "Invalid plan. Must be one of: basic, pro, elite",
    };
  }

  const provider = String(body.provider || "flutterwave")
    .trim()
    .toLowerCase();
  if (provider !== "flutterwave") {
    return {
      ok: false,
      status: 400,
      error: "Unsupported provider. Only flutterwave is supported.",
    };
  }

  const receiptId = String(body.receiptId || "").trim();
  if (!receiptId) {
    return { ok: false, status: 400, error: "receiptId is required" };
  }

  const txId = _extractFlutterwaveTxIdFromReceipt(receiptId);
  if (!txId) {
    return { ok: false, status: 400, error: "Invalid receiptId" };
  }

  const verify = await _verifyFlutterwaveTransaction(env, txId);

  if (verify.planId !== requestedPlan) {
    return {
      ok: false,
      status: 403,
      error: `Plan mismatch. Payment is for "${verify.planId}" but request is "${requestedPlan}".`,
    };
  }

  const txRefUid = _uidFromTxRef(verify.txRef);
  if (txRefUid && txRefUid !== verified.uid) {
    return {
      ok: false,
      status: 403,
      error: "Payment receipt does not belong to the signed-in user.",
    };
  }

  const firebaseEmail = (verified.email || "").trim().toLowerCase();
  const flwEmail = (verify.customerEmail || "").trim().toLowerCase();
  if (firebaseEmail && flwEmail && firebaseEmail !== flwEmail) {
    return {
      ok: false,
      status: 403,
      error: "Payment customer email does not match signed-in user.",
    };
  }

  const nowMs = Date.now();
  let existing = {};
  try {
    existing = await _lookupExistingCustomClaims(env, verified.uid);
  } catch (_) {
    existing = {};
  }

  const existingActive = existing && existing.organizerPro === true;
  const existingExpiryMs =
    existing && typeof existing.organizerProExpiryMs === "number"
      ? existing.organizerProExpiryMs
      : 0;
  const existingPlan = _normalizePlan(
    existing && typeof existing.organizerProPlan === "string"
      ? existing.organizerProPlan
      : ""
  );

  const hasActiveExisting =
    existingActive &&
    existingExpiryMs > nowMs &&
    _planOrder(existingPlan) > 0;

  const effectivePlan =
    hasActiveExisting &&
    _planOrder(existingPlan) > _planOrder(requestedPlan)
      ? existingPlan
      : requestedPlan;

  const durationDays = 90;
  const durationMs = durationDays * 24 * 60 * 60 * 1000;

  const baseMs = existingExpiryMs > nowMs ? existingExpiryMs : nowMs;
  const newExpiryMs = baseMs + durationMs;

  const nextClaims = {
    ...existing,
    organizerPro: true,
    organizerProPlan: effectivePlan,
    organizerProExpiryMs: newExpiryMs,
  };

  await _setFirebaseCustomClaims(env, verified.uid, nextClaims);

  return {
    ok: true,
    uid: verified.uid,
    requestedPlan,
    plan: effectivePlan,
    expiresAtMs: newExpiryMs,
    extendedFromMs: baseMs,
    txRef: verify.txRef,
    provider: "flutterwave",
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM ACTIVATION (NEW) — server-side verified
// ─────────────────────────────────────────────────────────────────────────────

async function _readPricingConfig(env) {
  const result = await _firestoreGetDocSA(env, "app_config/pricing");

  const defaults = {
    ngn: { premiumFee: 5000, premiumDurationDays: 30, premiumEnabled: true },
    usd: { premiumFee: 9.99, premiumDurationDays: 30, premiumEnabled: true },
  };

  if (!result.ok || !result.doc || !result.doc.fields) {
    return defaults;
  }

  const fields = result.doc.fields;

  function readMapField(fieldName) {
    const f = fields[fieldName];
    if (!f || !f.mapValue || !f.mapValue.fields) return {};
    const map = f.mapValue.fields;
    const out = {};
    for (const [k, v] of Object.entries(map)) {
      if (v.integerValue !== undefined) out[k] = parseInt(v.integerValue, 10);
      else if (v.doubleValue !== undefined) out[k] = v.doubleValue;
      else if (v.booleanValue !== undefined) out[k] = v.booleanValue;
      else if (v.stringValue !== undefined) out[k] = v.stringValue;
    }
    return out;
  }

  const ngnMap = readMapField("ngn");
  const usdMap = readMapField("usd");

  return {
    ngn: {
      premiumFee:
        typeof ngnMap.premiumFee === "number"
          ? ngnMap.premiumFee
          : defaults.ngn.premiumFee,
      premiumDurationDays:
        typeof ngnMap.premiumDurationDays === "number"
          ? ngnMap.premiumDurationDays
          : defaults.ngn.premiumDurationDays,
      premiumEnabled:
        typeof ngnMap.premiumEnabled === "boolean"
          ? ngnMap.premiumEnabled
          : defaults.ngn.premiumEnabled,
    },
    usd: {
      premiumFee:
        typeof usdMap.premiumFee === "number"
          ? usdMap.premiumFee
          : defaults.usd.premiumFee,
      premiumDurationDays:
        typeof usdMap.premiumDurationDays === "number"
          ? usdMap.premiumDurationDays
          : defaults.usd.premiumDurationDays,
      premiumEnabled:
        typeof usdMap.premiumEnabled === "boolean"
          ? usdMap.premiumEnabled
          : defaults.usd.premiumEnabled,
    },
  };
}

async function _activatePremium(env, verified, body) {
  const provider = String(body.provider || "flutterwave")
    .trim()
    .toLowerCase();
  if (provider !== "flutterwave") {
    return {
      ok: false,
      status: 400,
      error: "Unsupported provider. Only flutterwave is supported.",
    };
  }

  const receiptId = String(body.receiptId || "").trim();
  if (!receiptId) {
    return { ok: false, status: 400, error: "receiptId is required" };
  }

  const transactionId = String(body.transactionId || "").trim();
  const txId = transactionId || _extractFlutterwaveTxIdFromReceipt(receiptId);
  if (!txId) {
    return { ok: false, status: 400, error: "Invalid receiptId / transactionId" };
  }

  // 1. Verify with Flutterwave
  const verify = await _verifyFlutterwaveTransactionGeneric(env, txId);

  if (!verify.ok) {
    return {
      ok: false,
      status: 403,
      error: `Payment not successful (status=${verify.topStatus}, data.status=${verify.paymentStatus})`,
    };
  }

  // 2. Validate tx_ref starts with EH-PRM-
  if (!verify.txRef.startsWith("EH-PRM-")) {
    return {
      ok: false,
      status: 403,
      error: "Transaction is not a premium purchase (invalid tx_ref prefix).",
    };
  }

  // 3. Validate currency
  if (!verify.currency || !["NGN", "USD"].includes(verify.currency)) {
    return {
      ok: false,
      status: 403,
      error: "Unsupported currency.",
    };
  }

  // 4. Validate amount against pricing config
  const pricing = await _readPricingConfig(env);
  const planForCurrency =
    verify.currency === "NGN" ? pricing.ngn : pricing.usd;

  if (!planForCurrency.premiumEnabled) {
    return {
      ok: false,
      status: 403,
      error: "Premium is currently disabled for this currency.",
    };
  }

  const expectedFee = planForCurrency.premiumFee;
  const tolerance = 0.01;
  if (
    verify.amount == null ||
    verify.amount < expectedFee - tolerance
  ) {
    return {
      ok: false,
      status: 403,
      error: `Amount mismatch. Expected at least ${expectedFee} ${verify.currency}, got ${verify.amount}.`,
    };
  }

  // 5. Check email match
  const firebaseEmail = (verified.email || "").trim().toLowerCase();
  const flwEmail = (verify.customerEmail || "").trim().toLowerCase();
  if (
    firebaseEmail &&
    flwEmail &&
    !flwEmail.endsWith("@eleaguehub.app") &&
    firebaseEmail !== flwEmail
  ) {
    return {
      ok: false,
      status: 403,
      error: "Payment customer email does not match signed-in user.",
    };
  }

  // 6. Compute expiry
  const durationDays = planForCurrency.premiumDurationDays || 30;
  const nowMs = Date.now();

  // Check existing premium — extend if still active
  let existingExpiryMs = 0;
  try {
    const userDocResult = await _firestoreGetDocSA(
      env,
      `users/${verified.uid}`
    );
    if (
      userDocResult.ok &&
      userDocResult.doc &&
      userDocResult.doc.fields
    ) {
      const exField = userDocResult.doc.fields.premiumExpiresAtMs;
      if (exField && exField.integerValue) {
        existingExpiryMs = parseInt(exField.integerValue, 10);
      }
    }
  } catch (_) {
    // ignore
  }

  const baseMs = existingExpiryMs > nowMs ? existingExpiryMs : nowMs;
  const newExpiryMs = baseMs + durationDays * 24 * 60 * 60 * 1000;

  // 7. Write to Firestore via service account (bypasses client rules)
  await _firestorePatchDoc(env, `users/${verified.uid}`, {
    isPremium: true,
    premiumExpiresAtMs: newExpiryMs,
    premiumProvider: "flutterwave",
    premiumReceiptId: receiptId,
    premiumTxRef: verify.txRef,
    premiumActivatedAtMs: nowMs,
    updatedAt: { _serverTimestamp: true },
  });

  return {
    ok: true,
    uid: verified.uid,
    premiumExpiresAtMs: newExpiryMs,
    durationDays,
    currency: verify.currency,
    amount: verify.amount,
    txRef: verify.txRef,
    provider: "flutterwave",
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary signing (existing)
// ─────────────────────────────────────────────────────────────────────────────

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
  const entries = Object.entries(params)
    .filter(
      ([k, v]) => v !== undefined && v !== null && String(v).trim() !== ""
    )
    .map(([k, v]) => [String(k), String(v)]);

  entries.sort((a, b) => a[0].localeCompare(b[0]));
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
    return {
      ok: false,
      status: res.status,
      error: txt || `Firestore GET failed ${res.status}`,
    };
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
  const f = String(folder || "")
    .trim()
    .replace(/^\/+/, "");
  const parts = f.split("/").filter(Boolean);
  if (parts.length !== 4) return null;
  if (parts[0] !== "match_highlights") return null;
  return {
    leagueId: parts[1],
    matchId: parts[2],
    teamId: parts[3],
    folder: f,
  };
}

const _rate = {
  map: new Map(),
};

function _rateKey(uid, leagueId, matchId) {
  return `${uid}::${leagueId}::${matchId}`;
}

function _checkRate(uid, leagueId, matchId) {
  const now = Date.now();
  const key = _rateKey(uid, leagueId, matchId);
  const windowMs = 60 * 60 * 1000;
  const max = 6;

  const cur = _rate.map.get(key);
  if (!cur || now > cur.resetAtMs) {
    _rate.map.set(key, { count: 1, resetAtMs: now + windowMs });
    return { ok: true };
  }

  if (cur.count >= max) {
    return {
      ok: false,
      error: "Rate limit exceeded. Please try again later.",
    };
  }

  cur.count += 1;
  _rate.map.set(key, cur);
  return { ok: true };
}

function _isSafeCloudinaryPublicIdLeaf(publicId) {
  const s = String(publicId || "").trim();
  if (!s) return false;
  if (s.includes("/")) return false;
  return /^[A-Za-z0-9_-]{6,200}$/.test(s);
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTER
// ─────────────────────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS } });
    }

    const url = new URL(request.url);

    // ── LiveKit token ────────────────────────────────────────────────────
    if (url.pathname === "/" && request.method === "POST") {
      if (
        !env.LIVEKIT_URL ||
        !env.LIVEKIT_API_KEY ||
        !env.LIVEKIT_API_SECRET
      ) {
        return jsonResponse(
          { error: "Worker missing LiveKit env vars" },
          500
        );
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const userId = (body.userId || "").toString().trim();
      const role = (body.role || "participant").toString().trim();
      const side = (body.side || "").toString().trim();
      const roomName = resolveRoomName(body);

      if (!userId) {
        return jsonResponse({ error: "userId required" }, 400);
      }

      if (!roomName) {
        return jsonResponse(
          {
            error:
              "One of leagueId, matchId, callId, or roomName is required",
          },
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

      const at = new AccessToken(
        env.LIVEKIT_API_KEY,
        env.LIVEKIT_API_SECRET,
        {
          identity: userId,
          ttl: "2h",
          metadata,
        }
      );

      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,
        canPublish: true,
        roomAdmin: role === "host",
      });

      const token = await at.toJwt();

      return jsonResponse({
        token,
        url: env.LIVEKIT_URL,
        roomName,
        role,
        kind,
      });
    }

    // ── LiveKit admin ────────────────────────────────────────────────────
    if (url.pathname === "/admin" && request.method === "POST") {
      if (
        !env.LIVEKIT_URL ||
        !env.LIVEKIT_API_KEY ||
        !env.LIVEKIT_API_SECRET
      ) {
        return jsonResponse(
          { error: "Worker missing LiveKit env vars" },
          500
        );
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const action = (body.action || "").toString().trim();
      const targetUserId = (body.targetUserId || "").toString().trim();
      const roomName = resolveRoomName(body);

      if (!action || !targetUserId) {
        return jsonResponse(
          { error: "action, targetUserId required" },
          400
        );
      }

      if (!roomName) {
        return jsonResponse(
          {
            error:
              "One of leagueId, matchId, callId, or roomName is required",
          },
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

    // ── Organizer Pro activation ─────────────────────────────────────────
    if (
      url.pathname === "/organizer-pro/activate" &&
      request.method === "POST"
    ) {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse(
          { error: verified.error },
          verified.status || 401
        );
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      try {
        const out = await _activateOrganizerPro(env, verified, body || {});
        if (!out.ok)
          return jsonResponse({ error: out.error }, out.status || 400);
        return jsonResponse(out, 200);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    // ── PREMIUM ACTIVATION (NEW) ─────────────────────────────────────────
    if (url.pathname === "/premium/activate" && request.method === "POST") {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse(
          { error: verified.error },
          verified.status || 401
        );
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      try {
        const out = await _activatePremium(env, verified, body || {});
        if (!out.ok)
          return jsonResponse({ error: out.error }, out.status || 400);
        return jsonResponse(out, 200);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    // ── Cloudinary signing ───────────────────────────────────────────────
    if (url.pathname === "/cloudinary/sign" && request.method === "POST") {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse(
          { error: verified.error },
          verified.status || 401
        );
      }

      const cloudName = String(env.CLOUDINARY_CLOUD_NAME || "").trim();
      const apiKey = String(env.CLOUDINARY_API_KEY || "").trim();
      const apiSecret = String(env.CLOUDINARY_API_SECRET || "").trim();

      if (!cloudName || !apiKey || !apiSecret) {
        return jsonResponse(
          { error: "Worker missing Cloudinary env vars" },
          500
        );
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      const paramsIn =
        body && body.params && typeof body.params === "object"
          ? body.params
          : body;

      const folderRaw = _sanitizeCloudinaryPathPart(
        paramsIn.folder || ""
      ).replace(/^\/+/, "");
      const parsed = _parseMatchHighlightsFolder(folderRaw);

      if (!parsed) {
        return jsonResponse(
          {
            error:
              "Invalid folder. Expected match_highlights/{leagueId}/{matchId}/{teamId}",
          },
          400
        );
      }

      const publicId = _sanitizeCloudinaryPathPart(
        paramsIn.public_id || paramsIn.publicId || ""
      ).replace(/^\/+/, "");
      if (!_isSafeCloudinaryPublicIdLeaf(publicId)) {
        return jsonResponse({ error: "Invalid public_id" }, 400);
      }

      const overwrite =
        paramsIn.overwrite === true ||
        String(paramsIn.overwrite).toLowerCase() === "true";
      if (!overwrite) {
        return jsonResponse({ error: "overwrite must be true" }, 400);
      }
      if (
        paramsIn.transformation ||
        paramsIn.tags ||
        paramsIn.eager ||
        paramsIn.streaming_profile
      ) {
        return jsonResponse(
          {
            error:
              "Transformations/tags are not allowed for highlights",
          },
          400
        );
      }

      const rl = _checkRate(
        verified.uid,
        parsed.leagueId,
        parsed.matchId
      );
      if (!rl.ok) {
        return jsonResponse({ error: rl.error }, 429);
      }

      const membershipPath = `leagues/${parsed.leagueId}/memberships/${verified.uid}`;
      const matchPath = `leagues/${parsed.leagueId}/matches/${parsed.matchId}`;

      const memRes = await _firestoreGetDoc(
        env,
        verified.token,
        membershipPath
      );
      if (!memRes.ok) {
        return jsonResponse(
          { error: "Not allowed (membership not found)" },
          403
        );
      }

      const memTeamId = _fsString(memRes.doc, "teamId");
      if (!memTeamId || memTeamId !== parsed.teamId) {
        return jsonResponse(
          { error: "Not allowed (team mismatch)" },
          403
        );
      }

      const matchRes = await _firestoreGetDoc(
        env,
        verified.token,
        matchPath
      );
      if (!matchRes.ok) {
        return jsonResponse(
          { error: "Not allowed (match not found)" },
          403
        );
      }

      const isPlayed = _fsBool(matchRes.doc, "isPlayed");
      const status = _fsString(matchRes.doc, "status");
      const matchStatus = _fsString(matchRes.doc, "matchStatus");

      const finished =
        isPlayed === true ||
        status === "FINISHED" ||
        matchStatus === "FINISHED";
      if (!finished) {
        return jsonResponse(
          { error: "Not allowed (match not finished)" },
          403
        );
      }

      const homeTeamId = _fsString(matchRes.doc, "homeTeamId");
      const awayTeamId = _fsString(matchRes.doc, "awayTeamId");

      const isParticipant =
        memTeamId === homeTeamId || memTeamId === awayTeamId;
      if (!isParticipant) {
        return jsonResponse(
          { error: "Not allowed (team did not participate)" },
          403
        );
      }

      const nowSec = Math.floor(Date.now() / 1000);

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
        uploadUrl: `https://api.cloudinary.com/v1_1/${cloudName}/video/upload`,
        params: paramsToSign,
      });
    }

    return textResponse("Not found", 404);
  },
};
