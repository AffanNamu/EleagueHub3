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
  if (u.startsWith("wss://")) return "https://" + u.slice(6);
  if (u.startsWith("ws://")) return "http://" + u.slice(5);
  if (u.startsWith("https://") || u.startsWith("http://")) return u;
  return `https://${u}`;
}

async function makeAdminJwt(env, roomName) {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: "worker-admin",
    ttl: "5m",
  });
  at.addGrant({ room: roomName, roomAdmin: true });
  return at.toJwt();
}

async function mutePublishedTrack(env, roomName, identity, muted) {
  const adminJwt = await makeAdminJwt(env, roomName);
  const httpBase = toHttpBaseUrl(env.LIVEKIT_URL);
  const res = await fetch(`${httpBase}/twirp/livekit.RoomService/MutePublishedTrack`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${adminJwt}` },
    body: JSON.stringify({ room: roomName, identity, muted }),
  });
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
// Firebase ID Token verification (fixed X.509 cert handling)
// ─────────────────────────────────────────────────────────────────────────────

let _firebaseCertCache = { keysByKid: new Map(), expiresAtMs: 0 };

function _b64UrlToUint8Array(b64url) {
  const s = String(b64url || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = s.padEnd(Math.ceil(s.length / 4) * 4, "=");
  const bin = atob(padded);
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

function _pemToArrayBuffer(pem) {
  const lines = String(pem || "").trim().split("\n")
    .map(l => l.trim())
    .filter(l => l && !l.startsWith("-----"));
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
  if (!res.ok) throw new Error(`Failed to fetch Firebase certs: ${res.status}`);

  const maxAge = _parseCacheControlMaxAgeSeconds(res.headers.get("cache-control"));
  const json = await res.json();
  const map = new Map();

  for (const [kid, certPem] of Object.entries(json || {})) {
    try {
      // Google returns X.509 certificates, import as x509/spki
      const der = _pemToArrayBuffer(certPem);
      const key = await crypto.subtle.importKey(
        "spki",
        der,
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"]
      );
      map.set(kid, key);
    } catch (e1) {
      // Some Workers runtimes need the raw certificate parsed differently
      // Try importing as raw x509 via alternate method
      try {
        const certDer = _pemToArrayBuffer(certPem);
        // Extract the SubjectPublicKeyInfo from the X.509 certificate
        const spkiDer = _extractSpkiFromX509(certDer);
        if (spkiDer) {
          const key = await crypto.subtle.importKey(
            "spki",
            spkiDer,
            { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
            false,
            ["verify"]
          );
          map.set(kid, key);
        }
      } catch (e2) {
        // Skip this cert - will fail at verification time if needed
        console.error(`Failed to import cert for kid=${kid}: ${e1.message}, fallback: ${e2.message}`);
      }
    }
  }

  _firebaseCertCache = {
    keysByKid: map,
    expiresAtMs: now + Math.max(60, maxAge) * 1000,
  };

  return map;
}

// Extract SubjectPublicKeyInfo from a DER-encoded X.509 certificate
// X.509 structure: SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
// tbsCertificate: SEQUENCE { version, serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo, ... }
function _extractSpkiFromX509(certDerBuffer) {
  const bytes = new Uint8Array(certDerBuffer);
  let offset = 0;

  function readTag() {
    if (offset >= bytes.length) return null;
    const tag = bytes[offset++];
    return tag;
  }

  function readLength() {
    if (offset >= bytes.length) return 0;
    let len = bytes[offset++];
    if (len < 0x80) return len;
    const numBytes = len & 0x7f;
    len = 0;
    for (let i = 0; i < numBytes; i++) {
      len = (len << 8) | bytes[offset++];
    }
    return len;
  }

  function skipTlv() {
    readTag();
    const len = readLength();
    offset += len;
  }

  function readTlvBytes() {
    const start = offset;
    readTag();
    const len = readLength();
    const end = offset + len;
    offset = end;
    return bytes.slice(start, end);
  }

  try {
    // Outer SEQUENCE (Certificate)
    readTag(); // 0x30
    readLength();

    // tbsCertificate SEQUENCE
    readTag(); // 0x30
    readLength();

    // version [0] EXPLICIT (optional - check if context tag 0xa0)
    if (bytes[offset] === 0xa0) {
      skipTlv();
    }

    // serialNumber INTEGER
    skipTlv();

    // signature AlgorithmIdentifier SEQUENCE
    skipTlv();

    // issuer Name SEQUENCE
    skipTlv();

    // validity SEQUENCE
    skipTlv();

    // subject Name SEQUENCE
    skipTlv();

    // subjectPublicKeyInfo SEQUENCE - this is what we want
    const spkiBytes = readTlvBytes();
    return spkiBytes.buffer.slice(spkiBytes.byteOffset, spkiBytes.byteOffset + spkiBytes.byteLength);
  } catch (e) {
    return null;
  }
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
  if (!projectId) throw new Error("Worker missing FIREBASE_PROJECT_ID env var");

  const auth = request.headers.get("authorization") || request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return { ok: false, status: 401, error: "Missing Authorization: Bearer <Firebase ID token>" };

  const token = m[1].trim();
  if (!token) return { ok: false, status: 401, error: "Empty bearer token" };

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

  if (payload.aud !== projectId) return { ok: false, status: 401, error: "Invalid token audience" };
  if (payload.iss !== iss) return { ok: false, status: 401, error: "Invalid token issuer" };
  if (!payload.sub || typeof payload.sub !== "string") return { ok: false, status: 401, error: "Invalid token subject" };
  if (payload.exp && typeof payload.exp === "number" && payload.exp < nowSec) return { ok: false, status: 401, error: "Token expired" };
  if (payload.iat && typeof payload.iat === "number" && payload.iat > nowSec + 60) return { ok: false, status: 401, error: "Token issued in the future" };

  let keys;
  try {
    keys = await _loadFirebaseCerts();
  } catch (e) {
    return { ok: false, status: 503, error: "Unable to load Firebase public keys: " + e.message };
  }

  const key = keys.get(kid);
  if (!key) {
    return { ok: false, status: 401, error: "Unknown key id (kid). Available: " + [...keys.keys()].join(", ") };
  }

  let valid = false;
  try {
    valid = await crypto.subtle.verify({ name: "RSASSA-PKCS1-v1_5" }, key, signature, signingInput);
  } catch (e) {
    return { ok: false, status: 401, error: "Signature verification error: " + e.message };
  }

  if (!valid) return { ok: false, status: 401, error: "Invalid token signature" };

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
// Service Account helpers
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
  if (_saSigningKeyCache.key && _saSigningKeyCache.forEmail === email) return _saSigningKeyCache.key;

  const pem = _serviceAccountPrivateKeyPem(env);
  const der = _pemToArrayBuffer(pem);
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  _saSigningKeyCache = { key, forEmail: email };
  return key;
}

async function _signRs256(env, signingInputUtf8) {
  const key = await _importServiceAccountSigningKey(env);
  const data = new TextEncoder().encode(String(signingInputUtf8 || ""));
  const sig = await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, key, data);
  return _uint8ArrayToB64Url(new Uint8Array(sig));
}

async function _serviceAccountAccessToken(env) {
  const now = Date.now();
  if (_googleAccessTokenCache.accessToken && now + 15000 < _googleAccessTokenCache.expiresAtMs) {
    return _googleAccessTokenCache.accessToken;
  }

  const tokenUri = String(env.FIREBASE_TOKEN_URI || "https://oauth2.googleapis.com/token").trim();
  const clientEmail = _requireEnvString(env, "FIREBASE_CLIENT_EMAIL");

  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail, sub: clientEmail, aud: tokenUri,
    iat, exp,
    scope: "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/datastore",
  };

  const encodedHeader = _utf8ToB64Url(JSON.stringify(header));
  const encodedPayload = _utf8ToB64Url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await _signRs256(env, signingInput);
  const assertion = `${signingInput}.${signature}`;

  const body = new URLSearchParams();
  body.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  body.set("assertion", assertion);

  const res = await fetch(tokenUri, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: body.toString() });
  if (!res.ok) { const txt = await res.text(); throw new Error(`OAuth token failed (${res.status}): ${txt}`); }

  const json = await res.json();
  const accessToken = String(json.access_token || "").trim();
  if (!accessToken) throw new Error("OAuth response missing access_token");

  _googleAccessTokenCache = { accessToken, expiresAtMs: now + (json.expires_in || 3600) * 1000 };
  return accessToken;
}

// ─────────────────────────────────────────────────────────────────────────────
// Firebase Auth Custom Claims
// ─────────────────────────────────────────────────────────────────────────────

function _identityToolkitBase(env) {
  return `https://identitytoolkit.googleapis.com/v1/projects/${_requireEnvString(env, "FIREBASE_PROJECT_ID")}`;
}

async function _lookupExistingCustomClaims(env, uid) {
  const accessToken = await _serviceAccountAccessToken(env);
  const res = await fetch(`${_identityToolkitBase(env)}/accounts:lookup`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ localId: [String(uid).trim()] }),
  });
  if (!res.ok) { const txt = await res.text(); throw new Error(`accounts:lookup failed (${res.status}): ${txt}`); }
  const json = await res.json();
  const users = Array.isArray(json.users) ? json.users : [];
  if (users.length < 1) return {};
  try { return JSON.parse(users[0].customAttributes || "{}"); } catch (_) { return {}; }
}

async function _setFirebaseCustomClaims(env, uid, claimsObj) {
  const accessToken = await _serviceAccountAccessToken(env);
  const res = await fetch(`${_identityToolkitBase(env)}/accounts:update`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ localId: String(uid).trim(), customAttributes: JSON.stringify(claimsObj || {}) }),
  });
  if (!res.ok) { const txt = await res.text(); throw new Error(`accounts:update failed (${res.status}): ${txt}`); }
  return res.json();
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore REST API helpers
// ─────────────────────────────────────────────────────────────────────────────

function _firestoreRestBase(env) {
  return `https://firestore.googleapis.com/v1/projects/${_requireEnvString(env, "FIREBASE_PROJECT_ID")}/databases/(default)/documents`;
}

async function _firestorePatchDoc(env, docPath, fieldsObj) {
  const accessToken = await _serviceAccountAccessToken(env);
  const cleanPath = String(docPath).trim().replace(/^\/+/, "");
  const updateMaskParams = Object.keys(fieldsObj).map(k => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join("&");
  const url = `${_firestoreRestBase(env)}/${cleanPath}?${updateMaskParams}`;

  const firestoreFields = {};
  for (const [key, value] of Object.entries(fieldsObj)) {
    if (typeof value === "boolean") firestoreFields[key] = { booleanValue: value };
    else if (typeof value === "number" && Number.isInteger(value)) firestoreFields[key] = { integerValue: String(value) };
    else if (typeof value === "number") firestoreFields[key] = { doubleValue: value };
    else if (typeof value === "string") firestoreFields[key] = { stringValue: value };
    else if (value && typeof value === "object" && value._serverTimestamp) firestoreFields[key] = { timestampValue: new Date().toISOString() };
  }

  const res = await fetch(url, {
    method: "PATCH",
    headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ fields: firestoreFields }),
  });
  if (!res.ok) { const txt = await res.text(); throw new Error(`Firestore PATCH ${cleanPath} failed (${res.status}): ${txt}`); }
  return res.json();
}

async function _firestoreGetDocSA(env, docPath) {
  const accessToken = await _serviceAccountAccessToken(env);
  const cleanPath = String(docPath).trim().replace(/^\/+/, "");
  const res = await fetch(`${_firestoreRestBase(env)}/${cleanPath}`, {
    method: "GET",
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 404) return { ok: false, status: 404, doc: null };
  if (!res.ok) { const txt = await res.text(); return { ok: false, status: res.status, error: txt }; }
  return { ok: true, status: 200, doc: await res.json() };
}

// ─────────────────────────────────────────────────────────────────────────────
// Flutterwave verification
// ─────────────────────────────────────────────────────────────────────────────

function _normalizePlan(planId) {
  const p = String(planId || "").trim().toLowerCase();
  return (p === "basic" || p === "pro" || p === "elite") ? p : "";
}

function _planOrder(planId) {
  const p = String(planId || "").trim().toLowerCase();
  if (p === "basic") return 1; if (p === "pro") return 2; if (p === "elite") return 3; return 0;
}

function _planFromTxRef(txRef) {
  const m = String(txRef || "").match(/^EH-MLK-([A-Z]+)-/);
  return m ? _normalizePlan(m[1].toLowerCase()) : "";
}

function _extractFlutterwaveTxIdFromReceipt(receiptId) {
  const r = String(receiptId || "").trim();
  return (r.startsWith("FLW-") && r.length > 4) ? r.slice(4).trim() : r;
}

async function _verifyFlutterwaveTransactionGeneric(env, transactionId) {
  const secret = _requireEnvString(env, "FLUTTERWAVE_SECRET_KEY");
  const txId = String(transactionId || "").trim();
  if (!txId) throw new Error("Missing flutterwave transactionId");

  const res = await fetch(`https://api.flutterwave.com/v3/transactions/${encodeURIComponent(txId)}/verify`, {
    method: "GET",
    headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" },
  });
  if (!res.ok) { const txt = await res.text(); throw new Error(`Flutterwave verify failed (${res.status}): ${txt}`); }

  const json = await res.json();
  const data = json.data || {};
  const topStatus = String(json.status || "").trim().toLowerCase();
  const paymentStatus = String(data.status || "").trim().toLowerCase();
  const ok = topStatus === "success" && paymentStatus === "successful";

  return {
    ok, txId,
    txRef: String(data.tx_ref || "").trim(),
    currency: String(data.currency || "").trim().toUpperCase(),
    amount: typeof data.amount === "number" ? data.amount : null,
    customerEmail: (data.customer && typeof data.customer.email === "string") ? data.customer.email.trim() : "",
    paymentStatus, topStatus, raw: json,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Organizer Pro activation
// ─────────────────────────────────────────────────────────────────────────────

async function _activateOrganizerPro(env, verified, body) {
  const requestedPlan = _normalizePlan(body.plan);
  if (!requestedPlan) return { ok: false, status: 400, error: "Invalid plan" };

  const provider = String(body.provider || "flutterwave").trim().toLowerCase();
  if (provider !== "flutterwave") return { ok: false, status: 400, error: "Unsupported provider" };

  const receiptId = String(body.receiptId || "").trim();
  if (!receiptId) return { ok: false, status: 400, error: "receiptId required" };

  const txId = _extractFlutterwaveTxIdFromReceipt(receiptId);
  if (!txId) return { ok: false, status: 400, error: "Invalid receiptId" };

  const verify = await _verifyFlutterwaveTransactionGeneric(env, txId);
  if (!verify.ok) return { ok: false, status: 403, error: `Payment not successful (${verify.topStatus}/${verify.paymentStatus})` };

  if (!verify.txRef.startsWith("EH-MLK-")) return { ok: false, status: 403, error: "Not a Master League purchase" };

  const planFromRef = _planFromTxRef(verify.txRef);
  if (planFromRef && planFromRef !== requestedPlan) return { ok: false, status: 403, error: `Plan mismatch: payment=${planFromRef}, request=${requestedPlan}` };

  const nowMs = Date.now();
  let existing = {};
  try { existing = await _lookupExistingCustomClaims(env, verified.uid); } catch (_) {}

  const existingActive = existing.organizerPro === true;
  const existingExpiryMs = typeof existing.organizerProExpiryMs === "number" ? existing.organizerProExpiryMs : 0;
  const existingPlan = _normalizePlan(existing.organizerProPlan || "");
  const hasActiveExisting = existingActive && existingExpiryMs > nowMs && _planOrder(existingPlan) > 0;

  const effectivePlan = (hasActiveExisting && _planOrder(existingPlan) > _planOrder(requestedPlan)) ? existingPlan : requestedPlan;
  const durationMs = 90 * 24 * 60 * 60 * 1000;
  const baseMs = existingExpiryMs > nowMs ? existingExpiryMs : nowMs;
  const newExpiryMs = baseMs + durationMs;

  await _setFirebaseCustomClaims(env, verified.uid, {
    ...existing, organizerPro: true, organizerProPlan: effectivePlan, organizerProExpiryMs: newExpiryMs,
  });

  return { ok: true, uid: verified.uid, requestedPlan, plan: effectivePlan, expiresAtMs: newExpiryMs, txRef: verify.txRef, provider: "flutterwave" };
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium activation
// ─────────────────────────────────────────────────────────────────────────────

async function _readPricingConfig(env) {
  const defaults = {
    ngn: { premiumFee: 5000, premiumDurationDays: 30, premiumEnabled: true },
    usd: { premiumFee: 9.99, premiumDurationDays: 30, premiumEnabled: true },
  };
  try {
    const result = await _firestoreGetDocSA(env, "app_config/pricing");
    if (!result.ok || !result.doc || !result.doc.fields) return defaults;
    const fields = result.doc.fields;
    function readMap(name) {
      const f = fields[name];
      if (!f || !f.mapValue || !f.mapValue.fields) return {};
      const out = {};
      for (const [k, v] of Object.entries(f.mapValue.fields)) {
        if (v.integerValue !== undefined) out[k] = parseInt(v.integerValue, 10);
        else if (v.doubleValue !== undefined) out[k] = v.doubleValue;
        else if (v.booleanValue !== undefined) out[k] = v.booleanValue;
      }
      return out;
    }
    const n = readMap("ngn"), u = readMap("usd");
    return {
      ngn: { premiumFee: n.premiumFee ?? defaults.ngn.premiumFee, premiumDurationDays: n.premiumDurationDays ?? 30, premiumEnabled: n.premiumEnabled ?? true },
      usd: { premiumFee: u.premiumFee ?? defaults.usd.premiumFee, premiumDurationDays: u.premiumDurationDays ?? 30, premiumEnabled: u.premiumEnabled ?? true },
    };
  } catch (_) { return defaults; }
}

async function _activatePremium(env, verified, body) {
  const provider = String(body.provider || "flutterwave").trim().toLowerCase();
  if (provider !== "flutterwave") return { ok: false, status: 400, error: "Unsupported provider" };

  const receiptId = String(body.receiptId || "").trim();
  if (!receiptId) return { ok: false, status: 400, error: "receiptId required" };

  const txId = String(body.transactionId || "").trim() || _extractFlutterwaveTxIdFromReceipt(receiptId);
  if (!txId) return { ok: false, status: 400, error: "Invalid receiptId/transactionId" };

  const verify = await _verifyFlutterwaveTransactionGeneric(env, txId);
  if (!verify.ok) return { ok: false, status: 403, error: `Payment not successful (${verify.topStatus}/${verify.paymentStatus})` };
  if (!verify.txRef.startsWith("EH-PRM-")) return { ok: false, status: 403, error: "Not a premium purchase" };
  if (!verify.currency || !["NGN", "USD"].includes(verify.currency)) return { ok: false, status: 403, error: "Unsupported currency" };

  const pricing = await _readPricingConfig(env);
  const plan = verify.currency === "NGN" ? pricing.ngn : pricing.usd;
  if (verify.amount != null && verify.amount < plan.premiumFee - 0.01) {
    return { ok: false, status: 403, error: `Amount too low. Expected ${plan.premiumFee} ${verify.currency}, got ${verify.amount}` };
  }

  const nowMs = Date.now();
  let existingExpiryMs = 0;
  try {
    const r = await _firestoreGetDocSA(env, `users/${verified.uid}`);
    if (r.ok && r.doc && r.doc.fields && r.doc.fields.premiumExpiresAtMs && r.doc.fields.premiumExpiresAtMs.integerValue) {
      existingExpiryMs = parseInt(r.doc.fields.premiumExpiresAtMs.integerValue, 10);
    }
  } catch (_) {}

  const baseMs = existingExpiryMs > nowMs ? existingExpiryMs : nowMs;
  const newExpiryMs = baseMs + (plan.premiumDurationDays || 30) * 24 * 60 * 60 * 1000;

  await _firestorePatchDoc(env, `users/${verified.uid}`, {
    isPremium: true, premiumExpiresAtMs: newExpiryMs,
    premiumProvider: "flutterwave", premiumReceiptId: receiptId,
    premiumActivatedAtMs: nowMs, updatedAt: { _serverTimestamp: true },
  });

  return { ok: true, uid: verified.uid, premiumExpiresAtMs: newExpiryMs, durationDays: plan.premiumDurationDays, currency: verify.currency, amount: verify.amount, txRef: verify.txRef, provider: "flutterwave" };
}

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary signing
// ─────────────────────────────────────────────────────────────────────────────

function _sanitizeCloudinaryPathPart(s) {
  return String(s || "").trim().replace(/\s+/g, "_").replace(/[^a-zA-Z0-9_\-\/:.]/g, "_").replace(/\/{2,}/g, "/").slice(0, 240);
}

async function _sha1Hex(str) {
  const data = new TextEncoder().encode(String(str || ""));
  const digest = await crypto.subtle.digest("SHA-1", data);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

function _cloudinaryStringToSign(params) {
  return Object.entries(params).filter(([_, v]) => v != null && String(v).trim() !== "").map(([k, v]) => [String(k), String(v)]).sort((a, b) => a[0].localeCompare(b[0])).map(([k, v]) => `${k}=${v}`).join("&");
}

function _firestoreApiBase(env) {
  return `https://firestore.googleapis.com/v1/projects/${_requireEnvString(env, "FIREBASE_PROJECT_ID")}/databases/(default)/documents`;
}

async function _firestoreGetDoc(env, idToken, path) {
  const url = `${_firestoreApiBase(env)}/${path.replace(/^\/+/, "")}`;
  const res = await fetch(url, { method: "GET", headers: { authorization: `Bearer ${idToken}` } });
  if (res.status === 404) return { ok: false, status: 404, doc: null };
  if (!res.ok) return { ok: false, status: res.status, error: await res.text() };
  return { ok: true, status: 200, doc: await res.json() };
}

function _fsString(doc, field) { const v = doc && doc.fields && doc.fields[field]; return v && typeof v.stringValue === "string" ? v.stringValue : ""; }
function _fsBool(doc, field) { const v = doc && doc.fields && doc.fields[field]; return v && typeof v.booleanValue === "boolean" ? v.booleanValue : null; }

function _parseMatchHighlightsFolder(folder) {
  const parts = String(folder || "").trim().replace(/^\/+/, "").split("/").filter(Boolean);
  if (parts.length !== 4 || parts[0] !== "match_highlights") return null;
  return { leagueId: parts[1], matchId: parts[2], teamId: parts[3], folder: parts.join("/") };
}

const _rate = { map: new Map() };
function _checkRate(uid, leagueId, matchId) {
  const now = Date.now();
  const key = `${uid}::${leagueId}::${matchId}`;
  const cur = _rate.map.get(key);
  if (!cur || now > cur.resetAtMs) { _rate.map.set(key, { count: 1, resetAtMs: now + 3600000 }); return { ok: true }; }
  if (cur.count >= 6) return { ok: false, error: "Rate limit exceeded" };
  cur.count++; return { ok: true };
}

function _isSafeCloudinaryPublicIdLeaf(publicId) {
  const s = String(publicId || "").trim();
  return s && !s.includes("/") && /^[A-Za-z0-9_-]{6,200}$/.test(s);
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTER
// ─────────────────────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    // ── LiveKit token ────────────────────────────────────────────────────
    if (url.pathname === "/" && request.method === "POST") {
      if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
        return jsonResponse({ error: "Worker missing LiveKit env vars" }, 500);
      }
      let body; try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid JSON" }, 400); }
      const userId = (body.userId || "").toString().trim();
      const role = (body.role || "participant").toString().trim();
      const side = (body.side || "").toString().trim();
      const roomName = resolveRoomName(body);
      if (!userId) return jsonResponse({ error: "userId required" }, 400);
      if (!roomName) return jsonResponse({ error: "roomName required" }, 400);

      const kind = kindFrom(body, roomName);
      const metadata = JSON.stringify({ role, side: side || null, leagueId: (body.leagueId || "").toString().trim() || null, matchId: (body.matchId || "").toString().trim() || null, callId: (body.callId || "").toString().trim() || null, kind });

      const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, { identity: userId, ttl: "2h", metadata });
      at.addGrant({ room: roomName, roomJoin: true, canSubscribe: true, canPublishData: true, canPublish: true, roomAdmin: role === "host" });
      return jsonResponse({ token: await at.toJwt(), url: env.LIVEKIT_URL, roomName, role, kind });
    }

    // ── LiveKit admin ────────────────────────────────────────────────────
    if (url.pathname === "/admin" && request.method === "POST") {
      if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) return jsonResponse({ error: "Worker missing LiveKit env vars" }, 500);
      let body; try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid JSON" }, 400); }
      const action = (body.action || "").toString().trim();
      const targetUserId = (body.targetUserId || "").toString().trim();
      const roomName = resolveRoomName(body);
      if (!action || !targetUserId) return jsonResponse({ error: "action, targetUserId required" }, 400);
      if (!roomName) return jsonResponse({ error: "roomName required" }, 400);
      try {
        if (action === "mute") return jsonResponse({ ok: true, action, out: await mutePublishedTrack(env, roomName, targetUserId, true) });
        if (action === "unmute") return jsonResponse({ ok: true, action, out: await mutePublishedTrack(env, roomName, targetUserId, false) });
        return jsonResponse({ error: "Unsupported action" }, 400);
      } catch (e) { return jsonResponse({ error: e.message }, 500); }
    }

    // ── Organizer Pro activation ─────────────────────────────────────────
    if (url.pathname === "/organizer-pro/activate" && request.method === "POST") {
      let verified;
      try { verified = await _verifyFirebaseIdToken(env, request); } catch (e) { return jsonResponse({ error: e.message }, 500); }
      if (!verified.ok) return jsonResponse({ error: verified.error }, verified.status || 401);
      let body; try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid JSON" }, 400); }
      try {
        const out = await _activateOrganizerPro(env, verified, body || {});
        return out.ok ? jsonResponse(out) : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) { return jsonResponse({ error: e.message }, 500); }
    }

    // ── Premium activation ───────────────────────────────────────────────
    if (url.pathname === "/premium/activate" && request.method === "POST") {
      let verified;
      try { verified = await _verifyFirebaseIdToken(env, request); } catch (e) { return jsonResponse({ error: e.message }, 500); }
      if (!verified.ok) return jsonResponse({ error: verified.error }, verified.status || 401);
      let body; try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid JSON" }, 400); }
      try {
        const out = await _activatePremium(env, verified, body || {});
        return out.ok ? jsonResponse(out) : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) { return jsonResponse({ error: e.message }, 500); }
    }

    // ── Cloudinary signing ───────────────────────────────────────────────
    if (url.pathname === "/cloudinary/sign" && request.method === "POST") {
      let verified;
      try { verified = await _verifyFirebaseIdToken(env, request); } catch (e) { return jsonResponse({ error: e.message }, 500); }
      if (!verified.ok) return jsonResponse({ error: verified.error }, verified.status || 401);

      const cloudName = String(env.CLOUDINARY_CLOUD_NAME || "").trim();
      const apiKey = String(env.CLOUDINARY_API_KEY || "").trim();
      const apiSecret = String(env.CLOUDINARY_API_SECRET || "").trim();
      if (!cloudName || !apiKey || !apiSecret) return jsonResponse({ error: "Worker missing Cloudinary env vars" }, 500);

      let body; try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid JSON" }, 400); }
      const paramsIn = (body && body.params && typeof body.params === "object") ? body.params : body;

      const folderRaw = _sanitizeCloudinaryPathPart(paramsIn.folder || "").replace(/^\/+/, "");
      const parsed = _parseMatchHighlightsFolder(folderRaw);
      if (!parsed) return jsonResponse({ error: "Invalid folder" }, 400);

      const publicId = _sanitizeCloudinaryPathPart(paramsIn.public_id || paramsIn.publicId || "").replace(/^\/+/, "");
      if (!_isSafeCloudinaryPublicIdLeaf(publicId)) return jsonResponse({ error: "Invalid public_id" }, 400);
      if (!(paramsIn.overwrite === true || String(paramsIn.overwrite).toLowerCase() === "true")) return jsonResponse({ error: "overwrite must be true" }, 400);
      if (paramsIn.transformation || paramsIn.tags || paramsIn.eager || paramsIn.streaming_profile) return jsonResponse({ error: "Not allowed" }, 400);

      const rl = _checkRate(verified.uid, parsed.leagueId, parsed.matchId);
      if (!rl.ok) return jsonResponse({ error: rl.error }, 429);

      const memRes = await _firestoreGetDoc(env, verified.token, `leagues/${parsed.leagueId}/memberships/${verified.uid}`);
      if (!memRes.ok) return jsonResponse({ error: "Not allowed (no membership)" }, 403);
      const memTeamId = _fsString(memRes.doc, "teamId");
      if (!memTeamId || memTeamId !== parsed.teamId) return jsonResponse({ error: "Not allowed (team mismatch)" }, 403);

      const matchRes = await _firestoreGetDoc(env, verified.token, `leagues/${parsed.leagueId}/matches/${parsed.matchId}`);
      if (!matchRes.ok) return jsonResponse({ error: "Not allowed (no match)" }, 403);
      if (!(_fsBool(matchRes.doc, "isPlayed") === true || _fsString(matchRes.doc, "status") === "FINISHED" || _fsString(matchRes.doc, "matchStatus") === "FINISHED")) return jsonResponse({ error: "Not allowed (match not finished)" }, 403);

      const homeTeamId = _fsString(matchRes.doc, "homeTeamId");
      const awayTeamId = _fsString(matchRes.doc, "awayTeamId");
      if (memTeamId !== homeTeamId && memTeamId !== awayTeamId) return jsonResponse({ error: "Not allowed (not participant)" }, 403);

      const nowSec = Math.floor(Date.now() / 1000);
      const paramsToSign = { folder: parsed.folder, public_id: publicId, overwrite: "true", timestamp: nowSec };
      const signature = await _sha1Hex(`${_cloudinaryStringToSign(paramsToSign)}${apiSecret}`);

      return jsonResponse({ ok: true, uid: verified.uid, cloudName, apiKey, timestamp: nowSec, signature, uploadUrl: `https://api.cloudinary.com/v1_1/${cloudName}/video/upload`, params: paramsToSign });
    }

    return textResponse("Not found", 404);
  },
};
