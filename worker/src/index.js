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
    headers: { ...CORS_HEADERS, ...extraHeaders },
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
  at.addGrant({ room: roomName, roomAdmin: true });
  return at.toJwt();
}

async function mutePublishedTrack(env, roomName, identity, muted) {
  const adminJwt = await makeAdminJwt(env, roomName);
  const httpBase = toHttpBaseUrl(env.LIVEKIT_URL);
  const res = await fetch(`${httpBase}/twirp/livekit.RoomService/MutePublishedTrack`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${adminJwt}`,
    },
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

let _firebaseCertCache = { keysByKid: new Map(), expiresAtMs: 0 };

function _base64UrlToBase64(input) {
  const s = String(input || "").trim().replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (s.length % 4)) % 4;
  return s + "=".repeat(padLen);
}

function _b64UrlToUint8Array(b64url) {
  const base64 = _base64UrlToBase64(b64url);
  const bin = atob(base64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) {
    bytes[i] = bin.charCodeAt(i);
  }
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

function _extractSpkiFromX509Der(derBuffer) {
  const bytes = new Uint8Array(derBuffer);
  let pos = 0;

  function readTagAndLength() {
    if (pos >= bytes.length) throw new Error("unexpected end");
    const tag = bytes[pos++];
    let len = bytes[pos++];
    if (len & 0x80) {
      const numLenBytes = len & 0x7f;
      len = 0;
      for (let i = 0; i < numLenBytes; i++) {
        len = (len << 8) | bytes[pos++];
      }
    }
    return { tag, len, start: pos };
  }

  function skipTlv() {
    const { len } = readTagAndLength();
    pos += len;
  }

  function readTlvRaw() {
    const rawStart = pos;
    const { len } = readTagAndLength();
    pos += len;
    return bytes.slice(rawStart, pos);
  }

  readTagAndLength();
  readTagAndLength();
  if (bytes[pos] === 0xa0) skipTlv();
  skipTlv();
  skipTlv();
  skipTlv();
  skipTlv();
  skipTlv();
  const spkiRaw = readTlvRaw();
  return spkiRaw.buffer.slice(
    spkiRaw.byteOffset,
    spkiRaw.byteOffset + spkiRaw.byteLength
  );
}

function _parseCacheControlMaxAgeSeconds(h) {
  const v = String(h || "");
  const m = v.match(/max-age=(\d+)/i);
  return m ? parseInt(m[1], 10) : 0;
}

async function _importPublicKeyFromCert(certPem) {
  const derBuf = _pemToDerBytes(certPem);
  try {
    return await crypto.subtle.importKey(
      "spki",
      derBuf,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );
  } catch (_) {}

  const spkiDer = _extractSpkiFromX509Der(derBuf);
  return await crypto.subtle.importKey(
    "spki",
    spkiDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
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
      const cryptoKey = await _importPublicKeyFromCert(certPem);
      map.set(kid, cryptoKey);
    } catch (e) {
      console.error(`[Firebase] Failed to import cert kid=${kid}: ${e.message}`);
    }
  }

  if (map.size === 0) {
    throw new Error("Failed to import any Firebase public certificates");
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

  const headerJson = new TextDecoder().decode(_b64UrlToUint8Array(parts[0]));
  const payloadJson = new TextDecoder().decode(_b64UrlToUint8Array(parts[1]));
  const header = JSON.parse(headerJson);
  const payload = JSON.parse(payloadJson);
  const signature = _b64UrlToUint8Array(parts[2]);
  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);

  return { header, payload, signature, signingInput };
}

async function _verifyFirebaseIdToken(env, request) {
  const projectId = String(env.FIREBASE_PROJECT_ID || "").trim();
  if (!projectId) throw new Error("Worker missing FIREBASE_PROJECT_ID env var");

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
  if (!token) return { ok: false, status: 401, error: "Empty bearer token" };

  let decoded;
  try {
    decoded = _decodeJwtParts(token);
  } catch (e) {
    return {
      ok: false,
      status: 401,
      error: `Invalid token (decode failed): ${e.message || String(e)}`,
    };
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

  let keys;
  try {
    keys = await _loadFirebaseCerts();
  } catch (e) {
    return {
      ok: false,
      status: 503,
      error: "Unable to load Firebase public keys: " + (e.message || String(e)),
    };
  }

  const key = keys.get(kid);
  if (!key) return { ok: false, status: 401, error: "Unknown key id (kid)" };

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
    throw new Error(`OAuth token failed (${res.status}): ${txt}`);
  }

  const json = await res.json();
  const accessToken = String(json.access_token || "").trim();
  if (!accessToken) throw new Error("OAuth response missing access_token");

  _googleAccessTokenCache = {
    accessToken,
    expiresAtMs: now + (json.expires_in || 3600) * 1000,
  };
  return accessToken;
}

function _identityToolkitBase(env) {
  return `https://identitytoolkit.googleapis.com/v1/projects/${_requireEnvString(env, "FIREBASE_PROJECT_ID")}`;
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
  try {
    return JSON.parse(users[0].customAttributes || "{}");
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

function _firestoreRestBase(env) {
  return `https://firestore.googleapis.com/v1/projects/${_requireEnvString(env, "FIREBASE_PROJECT_ID")}/databases/(default)/documents`;
}

function _toFirestoreValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number" && Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === "number") return { doubleValue: value };
  if (typeof value === "string") return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map((v) => _toFirestoreValue(v)) } };
  }
  if (value && typeof value === "object" && value._serverTimestamp) {
    return { timestampValue: new Date().toISOString() };
  }
  if (value && typeof value === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = _toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

function _fromFirestoreValue(v) {
  if (!v || typeof v !== "object") return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return parseInt(v.integerValue, 10);
  if ("doubleValue" in v) return v.doubleValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) {
    const values = Array.isArray(v.arrayValue.values) ? v.arrayValue.values : [];
    return values.map((item) => _fromFirestoreValue(item));
  }
  if ("mapValue" in v) {
    const fields = v.mapValue && v.mapValue.fields ? v.mapValue.fields : {};
    const out = {};
    for (const [k, item] of Object.entries(fields)) {
      out[k] = _fromFirestoreValue(item);
    }
    return out;
  }
  return null;
}

function _fromFirestoreDoc(doc) {
  const fields = doc && doc.fields ? doc.fields : {};
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    out[k] = _fromFirestoreValue(v);
  }
  return out;
}

async function _firestorePatchDoc(env, docPath, fieldsObj) {
  const accessToken = await _serviceAccountAccessToken(env);
  const cleanPath = String(docPath || "").trim().replace(/^\/+/, "");
  const updateMaskParams = Object.keys(fieldsObj)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join("&");
  const url = `${_firestoreRestBase(env)}/${cleanPath}?${updateMaskParams}`;
  const firestoreFields = {};
  for (const [key, value] of Object.entries(fieldsObj)) {
    firestoreFields[key] = _toFirestoreValue(value);
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
    throw new Error(`Firestore PATCH ${cleanPath} failed (${res.status}): ${txt}`);
  }
  return res.json();
}

async function _firestoreGetDocSA(env, docPath) {
  const accessToken = await _serviceAccountAccessToken(env);
  const cleanPath = String(docPath || "").trim().replace(/^\/+/, "");
  const res = await fetch(`${_firestoreRestBase(env)}/${cleanPath}`, {
    method: "GET",
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 404) return { ok: false, status: 404, doc: null };
  if (!res.ok) {
    const txt = await res.text();
    return { ok: false, status: res.status, error: txt };
  }
  return { ok: true, status: 200, doc: await res.json() };
}

async function _firestoreCreateDocSA(env, docPath, fieldsObj) {
  const accessToken = await _serviceAccountAccessToken(env);
  const cleanPath = String(docPath || "").trim().replace(/^\/+/, "");
  const url = `${_firestoreRestBase(env)}/${cleanPath}`;
  const firestoreFields = {};
  for (const [key, value] of Object.entries(fieldsObj)) {
    firestoreFields[key] = _toFirestoreValue(value);
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
    throw new Error(`Firestore create ${cleanPath} failed (${res.status}): ${txt}`);
  }

  return res.json();
}

function _moneyEqWithinTolerance(expected, actual, currency) {
  const c = String(currency || "").trim().toUpperCase();
  if (typeof expected !== "number" || typeof actual !== "number") return false;
  if (c === "NGN") return Math.abs(expected - actual) <= 1.0;
  return Math.abs(expected - actual) <= 0.02;
}

async function _verifyFlutterwaveTransactionGeneric(env, transactionId) {
  const secret = _requireEnvString(env, "FLUTTERWAVE_SECRET_KEY");
  const txId = String(transactionId || "").trim();
  if (!txId) throw new Error("Missing flutterwave transactionId");

  const res = await fetch(`https://api.flutterwave.com/v3/transactions/${encodeURIComponent(txId)}/verify`, {
    method: "GET",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
    },
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Flutterwave verify failed (${res.status}): ${txt}`);
  }

  const json = await res.json();
  const data = json.data || {};
  const topStatus = String(json.status || "").trim().toLowerCase();
  const paymentStatus = String(data.status || "").trim().toLowerCase();
  const ok = topStatus === "success" && paymentStatus === "successful";

  return {
    ok,
    txId,
    txRef: String(data.tx_ref || "").trim(),
    currency: String(data.currency || "").trim().toUpperCase(),
    amount: typeof data.amount === "number" ? data.amount : null,
    customerEmail:
      data.customer && typeof data.customer.email === "string"
        ? data.customer.email.trim()
        : "",
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
  if (!result.currency || !["NGN", "USD"].includes(result.currency)) {
    throw new Error("Unsupported currency");
  }
  if (result.amount == null || result.amount <= 0) {
    throw new Error("Invalid amount");
  }
  return result;
}

async function _readPricingConfig(env) {
  const defaults = {
    ngn: {
      createFee: 4000,
      accessFee: 1000,
      couponUnit: 1000,
      couponThreshold: null,
      couponDiscountPercent: 30,
      premiumFee: 5000,
      premiumDurationDays: 30,
      premiumEnabled: true,
      masterLeagueBasicFee: 1500,
      masterLeagueProFee: 3000,
      masterLeagueEliteFee: 5000,
      organizerVerificationFee: 10000,
      organizerVerificationEnabled: true,
      organizerVerificationRenewalFee: 8000,
      organizerVerificationRenewalEnabled: true,
      organizerVerificationDurationDays: 90,
      paymentsEnabled: true,
      flutterwaveEnabled: true,
    },
    usd: {
      createFee: 5.0,
      accessFee: 1.5,
      couponUnit: 1.5,
      couponThreshold: 20.0,
      couponDiscountPercent: 30,
      premiumFee: 9.99,
      premiumDurationDays: 30,
      premiumEnabled: true,
      masterLeagueBasicFee: 5.0,
      masterLeagueProFee: 10.0,
      masterLeagueEliteFee: 20.0,
      organizerVerificationFee: 15.0,
      organizerVerificationEnabled: true,
      organizerVerificationRenewalFee: 12.0,
      organizerVerificationRenewalEnabled: true,
      organizerVerificationDurationDays: 90,
      paymentsEnabled: true,
      flutterwaveEnabled: true,
    },
  };

  let result = await _firestoreGetDocSA(env, "app_config/pricing");
  if (!result.ok || !result.doc || !result.doc.fields) {
    result = await _firestoreGetDocSA(env, "app/pricing");
  }
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
      else if (v.stringValue !== undefined) out[k] = v.stringValue;
      else if (v.nullValue !== undefined) out[k] = null;
    }
    return out;
  }

  const n = readMap("ngn");
  const u = readMap("usd");

  function mergeCurrency(raw, dft) {
    return {
      ...dft,
      ...raw,
      masterLeagueBasicFee:
        raw.masterLeagueBasicFee ?? raw.masterLinkBasicFee ?? raw.masterLinkFee ?? raw.masterLeagueFee ?? dft.masterLeagueBasicFee,
      masterLeagueProFee:
        raw.masterLeagueProFee ?? raw.masterLinkProFee ?? raw.masterLinkFee ?? raw.masterLeagueFee ?? dft.masterLeagueProFee,
      masterLeagueEliteFee:
        raw.masterLeagueEliteFee ?? raw.masterLinkEliteFee ?? raw.masterLinkFee ?? raw.masterLeagueFee ?? dft.masterLeagueEliteFee,
      organizerVerificationFee:
        raw.organizerVerificationFee ?? raw.verificationFee ?? dft.organizerVerificationFee,
      organizerVerificationEnabled:
        typeof raw.organizerVerificationEnabled === "boolean"
          ? raw.organizerVerificationEnabled
          : (typeof raw.verificationEnabled === "boolean" ? raw.verificationEnabled : dft.organizerVerificationEnabled),
      organizerVerificationRenewalFee:
        raw.organizerVerificationRenewalFee ?? raw.verificationRenewalFee ?? dft.organizerVerificationRenewalFee,
      organizerVerificationRenewalEnabled:
        typeof raw.organizerVerificationRenewalEnabled === "boolean"
          ? raw.organizerVerificationRenewalEnabled
          : (typeof raw.verificationRenewalEnabled === "boolean"
              ? raw.verificationRenewalEnabled
              : dft.organizerVerificationRenewalEnabled),
      organizerVerificationDurationDays:
        raw.organizerVerificationDurationDays ?? raw.verificationDurationDays ?? dft.organizerVerificationDurationDays,
      paymentsEnabled:
        typeof raw.paymentsEnabled === "boolean" ? raw.paymentsEnabled : dft.paymentsEnabled,
      flutterwaveEnabled:
        typeof raw.flutterwaveEnabled === "boolean" ? raw.flutterwaveEnabled : dft.flutterwaveEnabled,
      premiumEnabled:
        typeof raw.premiumEnabled === "boolean" ? raw.premiumEnabled : dft.premiumEnabled,
      premiumFee:
        raw.premiumFee ?? dft.premiumFee,
      premiumDurationDays:
        raw.premiumDurationDays ?? dft.premiumDurationDays,
    };
  }

  return {
    ngn: mergeCurrency(n, defaults.ngn),
    usd: mergeCurrency(u, defaults.usd),
  };
}

function _pricingForCurrency(pricing, currency) {
  const c = String(currency || "").trim().toUpperCase();
  return c === "NGN" ? pricing.ngn : pricing.usd;
}

function _masterLeagueExpectedFee(planCfg, planId) {
  const p = String(planId || "").trim().toLowerCase();
  if (p === "basic") return Number(planCfg.masterLeagueBasicFee || 0);
  if (p === "pro") return Number(planCfg.masterLeagueProFee || 0);
  if (p === "elite") return Number(planCfg.masterLeagueEliteFee || 0);
  return 0;
}

async function _verifyMasterLeaguePayment(env, verified, body) {
  const attemptId = String(body.attemptId || "").trim();
  const transactionId = String(body.transactionId || "").trim();
  const txRefFromClient = String(body.txRef || "").trim();

  if (!attemptId) return { ok: false, status: 400, error: "attemptId is required" };
  if (!transactionId) return { ok: false, status: 400, error: "transactionId is required" };

  const attemptRes = await _firestoreGetDocSA(env, `payment_attempts/${attemptId}`);
  if (!attemptRes.ok || !attemptRes.doc) {
    return { ok: false, status: 404, error: "Payment attempt not found." };
  }

  const attempt = _fromFirestoreDoc(attemptRes.doc);
  const attemptUserId = String(attempt.userId || "").trim();
  if (!attemptUserId || attemptUserId !== verified.uid) {
    return { ok: false, status: 403, error: "Payment attempt does not belong to signed-in user." };
  }

  const existingPaymentId = String(attempt.paymentId || "").trim();
  if (existingPaymentId) {
    const existingPaymentRes = await _firestoreGetDocSA(env, `payments/${existingPaymentId}`);
    if (existingPaymentRes.ok && existingPaymentRes.doc) {
      const existingPayment = _fromFirestoreDoc(existingPaymentRes.doc);
      const existingVerification = existingPayment.verification || {};
      return {
        ok: true,
        success: existingVerification.verified === true,
        provider: "flutterwave",
        paymentId: existingPaymentId,
        receiptId: String(existingPayment.receiptId || "").trim(),
        paidAtMs: Number(existingPayment.paidAtMs || 0),
        transactionId: String(existingPayment.providerTransactionId || transactionId).trim(),
        txRef: String(existingPayment.txRef || txRefFromClient).trim(),
        status: String(existingPayment.status || "success").trim(),
        currency: String(existingPayment.currency || attempt.currency || "").trim(),
        amount: Number(existingPayment.amount || attempt.amount || 0),
        amountStr: String(existingPayment.amountStr || attempt.amountStr || "").trim(),
        raw: existingPayment.rawFlutterwaveVerification || {},
      };
    }
  }

  const verify = await _verifyFlutterwaveTransaction(env, transactionId);
  const pricing = await _readPricingConfig(env);
  const cfg = _pricingForCurrency(pricing, verify.currency);

  if (cfg.paymentsEnabled !== true) {
    return { ok: false, status: 403, error: "Payments are currently disabled." };
  }
  if (cfg.flutterwaveEnabled !== true) {
    return { ok: false, status: 403, error: "Flutterwave is currently disabled." };
  }

  const firebaseEmail = (verified.email || "").trim().toLowerCase();
  const flwEmail = (verify.customerEmail || "").trim().toLowerCase();
  if (firebaseEmail && flwEmail && !flwEmail.endsWith("@eleaguehub.app") && firebaseEmail !== flwEmail) {
    return { ok: false, status: 403, error: "Email mismatch." };
  }

  if (txRefFromClient && verify.txRef && txRefFromClient !== verify.txRef) {
    return { ok: false, status: 403, error: "txRef mismatch." };
  }

  const attemptProductType = String(attempt.productType || "").trim();
  const attemptMeta = attempt.metadata && typeof attempt.metadata === "object" ? attempt.metadata : {};
  const attemptCurrency = String(attempt.currency || "").trim().toUpperCase();
  const attemptAmount = Number(attempt.amount || 0);

  if (attemptCurrency && attemptCurrency !== verify.currency) {
    return { ok: false, status: 403, error: "Currency mismatch." };
  }

  if (attemptAmount > 0 && !_moneyEqWithinTolerance(attemptAmount, Number(verify.amount || 0), verify.currency)) {
    return {
      ok: false,
      status: 403,
      error: `Amount mismatch. Expected ${attemptAmount} ${verify.currency}, got ${verify.amount}.`,
    };
  }

  if (attemptProductType === "master_league_creation") {
    const planId = String(attemptMeta.plan || "").trim().toLowerCase();
    const expected = _masterLeagueExpectedFee(cfg, planId);
    if (!(expected > 0)) {
      return { ok: false, status: 403, error: "Master League plan pricing is not configured." };
    }
    if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
      return {
        ok: false,
        status: 403,
        error: `Master League amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
      };
    }
  }

  if (attemptProductType === "organizer_verification") {
    if (!cfg.organizerVerificationEnabled) {
      return { ok: false, status: 403, error: "Organizer verification is currently disabled." };
    }
    const expected = Number(cfg.organizerVerificationFee || 0);
    if (!(expected > 0)) {
      return { ok: false, status: 403, error: "Organizer verification pricing is not configured." };
    }
    if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
      return {
        ok: false,
        status: 403,
        error: `Organizer verification amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
      };
    }
  }

  if (attemptProductType === "organizer_verification_renewal") {
    if (!cfg.organizerVerificationRenewalEnabled) {
      return { ok: false, status: 403, error: "Organizer verification renewal is currently disabled." };
    }
    const expected = Number(cfg.organizerVerificationRenewalFee || 0);
    if (!(expected > 0)) {
      return { ok: false, status: 403, error: "Organizer verification renewal pricing is not configured." };
    }
    if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
      return {
        ok: false,
        status: 403,
        error: `Organizer verification renewal amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
      };
    }
  }

  const paidAtMs = Date.now();
  const paymentId = `flutterwave_${verify.txId}`;
  const receiptId = `FLW-${verify.txId}`;
  const attemptStatus = String(attempt.status || "").trim().toLowerCase();

  if (attemptStatus === "fulfilled" || attemptStatus === "verified") {
    const existingPaymentRes = await _firestoreGetDocSA(env, `payments/${paymentId}`);
    if (existingPaymentRes.ok && existingPaymentRes.doc) {
      const existingPayment = _fromFirestoreDoc(existingPaymentRes.doc);
      return {
        ok: true,
        success: true,
        provider: "flutterwave",
        paymentId,
        receiptId: String(existingPayment.receiptId || receiptId).trim(),
        paidAtMs: Number(existingPayment.paidAtMs || paidAtMs),
        transactionId: verify.txId,
        txRef: verify.txRef,
        status: "success",
        currency: verify.currency,
        amount: Number(verify.amount || 0),
        amountStr: String(existingPayment.amountStr || attempt.amountStr || "").trim(),
        raw: verify.raw || {},
      };
    }
  }

  await _firestoreCreateDocSA(env, `payments/${paymentId}`, {
    paymentId,
    attemptId,
    status: "success",
    provider: "flutterwave",
    providerTransactionId: verify.txId,
    txRef: verify.txRef,
    receiptId,
    userId: verified.uid,
    leagueId: String(attempt.leagueId || "").trim(),
    leagueName: String(attempt.leagueName || "").trim(),
    masterLeagueId: String(attempt.masterLeagueId || "").trim(),
    couponCode: String(attempt.couponCode || "").trim(),
    currency: verify.currency,
    amount: Number(verify.amount || attempt.amount || 0),
    amountStr: String(attempt.amountStr || "").trim(),
    items: Array.isArray(attempt.items) ? attempt.items : [],
    productType: String(attempt.productType || "").trim(),
    productSubType: String(attempt.productSubType || "").trim(),
    metadata: attempt.metadata && typeof attempt.metadata === "object" ? attempt.metadata : {},
    paidAtMs,
    createdAtMs: paidAtMs,
    updatedAtMs: paidAtMs,
    verification: {
      mode: "server",
      verified: true,
      verifiedAtMs: paidAtMs,
    },
    rawFlutterwaveVerification: verify.raw || {},
  });

  await _firestorePatchDoc(env, `payment_attempts/${attemptId}`, {
    status: "verified",
    paymentId,
    receiptId,
    paidAtMs,
    providerTransactionId: verify.txId,
    txRef: verify.txRef,
    updatedAtMs: paidAtMs,
  });

  return {
    ok: true,
    success: true,
    provider: "flutterwave",
    paymentId,
    receiptId,
    paidAtMs,
    transactionId: verify.txId,
    txRef: verify.txRef,
    status: "success",
    currency: verify.currency,
    amount: Number(verify.amount || 0),
    amountStr: String(attempt.amountStr || "").trim(),
    raw: verify.raw || {},
  };
}

async function _activateOrganizerPro(env, verified, body) {
  const uid = String(verified.uid || "").trim();
  const plan = String(body.plan || "").trim().toLowerCase();
  const provider = String(body.provider || "").trim().toLowerCase();
  const receiptId = String(body.receiptId || "").trim();

  if (!uid) return { ok: false, status: 401, error: "Unauthenticated." };
  if (!["basic", "pro", "elite"].includes(plan)) {
    return { ok: false, status: 400, error: "Invalid plan." };
  }
  if (provider !== "flutterwave") {
    return { ok: false, status: 400, error: "Unsupported provider." };
  }
  if (!receiptId) {
    return { ok: false, status: 400, error: "receiptId is required." };
  }

  const txId = receiptId.startsWith("FLW-") ? receiptId.slice(4).trim() : receiptId;
  if (!txId) {
    return { ok: false, status: 400, error: "Invalid receiptId." };
  }

  const verify = await _verifyFlutterwaveTransaction(env, txId);
  const pricing = await _readPricingConfig(env);
  const cfg = _pricingForCurrency(pricing, verify.currency);

  if (!cfg.paymentsEnabled) {
    return { ok: false, status: 403, error: "Payments are currently disabled." };
  }
  if (!cfg.flutterwaveEnabled) {
    return { ok: false, status: 403, error: "Flutterwave is currently disabled." };
  }

  const expected = _masterLeagueExpectedFee(cfg, plan);
  if (!(expected > 0)) {
    return { ok: false, status: 403, error: "Organizer Pro pricing is not configured." };
  }

  if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
    return {
      ok: false,
      status: 403,
      error: `Amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
    };
  }

  const nowMs = Date.now();
  const expiryMs = nowMs + 365 * 24 * 60 * 60 * 1000;

  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: plan,
    organizerProExpiryMs: expiryMs,
  };

  await _setFirebaseCustomClaims(env, uid, nextClaims);

  await _firestorePatchDoc(env, `users/${uid}/entitlements/master_league`, {
    active: true,
    plan,
    provider: "flutterwave",
    receiptId,
    transactionId: verify.txId,
    currency: verify.currency,
    amount: Number(verify.amount || 0),
    activatedAtMs: nowMs,
    expiresAtMs: expiryMs,
    updatedAtMs: nowMs,
  });

  return {
    ok: true,
    status: 200,
    success: true,
    uid,
    plan,
    expiryMs,
    provider: "flutterwave",
    receiptId,
    transactionId: verify.txId,
    currency: verify.currency,
    amount: Number(verify.amount || 0),
  };
}

async function _activatePremium(env, verified, body) {
  const uid = String(verified.uid || "").trim();
  const provider = String(body.provider || "").trim().toLowerCase();
  const receiptId = String(body.receiptId || "").trim();

  if (!uid) return { ok: false, status: 401, error: "Unauthenticated." };
  if (provider !== "flutterwave") {
    return { ok: false, status: 400, error: "Unsupported provider." };
  }
  if (!receiptId) {
    return { ok: false, status: 400, error: "receiptId is required." };
  }

  const txId = receiptId.startsWith("FLW-") ? receiptId.slice(4).trim() : receiptId;
  if (!txId) {
    return { ok: false, status: 400, error: "Invalid receiptId." };
  }

  const verify = await _verifyFlutterwaveTransaction(env, txId);
  const pricing = await _readPricingConfig(env);
  const cfg = _pricingForCurrency(pricing, verify.currency);

  if (!cfg.paymentsEnabled) {
    return { ok: false, status: 403, error: "Payments are currently disabled." };
  }
  if (!cfg.flutterwaveEnabled) {
    return { ok: false, status: 403, error: "Flutterwave is currently disabled." };
  }
  if (!cfg.premiumEnabled) {
    return { ok: false, status: 403, error: "Premium is currently disabled." };
  }

  const expected = Number(cfg.premiumFee || 0);
  if (!(expected > 0)) {
    return { ok: false, status: 403, error: "Premium pricing is not configured." };
  }

  if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
    return {
      ok: false,
      status: 403,
      error: `Premium amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
    };
  }

  const nowMs = Date.now();
  const durationDays = Number(cfg.premiumDurationDays || 30);
  const expiresAtMs = nowMs + durationDays * 24 * 60 * 60 * 1000;

  await _firestorePatchDoc(env, `users/${uid}`, {
    isPremium: true,
    premiumExpiresAtMs: expiresAtMs,
    updatedAt: nowMs,
  });

  return {
    ok: true,
    status: 200,
    success: true,
    uid,
    provider: "flutterwave",
    receiptId,
    transactionId: verify.txId,
    currency: verify.currency,
    amount: Number(verify.amount || 0),
    premiumExpiresAtMs: expiresAtMs,
  };
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS } });
    }

    const url = new URL(request.url);

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
      const role = (body.role || "participant").toString().trim();
      const side = (body.side || "").toString().trim();
      const roomName = resolveRoomName(body);

      if (!userId) return jsonResponse({ error: "userId required" }, 400);
      if (!roomName) {
        return jsonResponse(
          { error: "One of leagueId, matchId, callId, or roomName is required" },
          400
        );
      }

      const kind = kindFrom(body, roomName);
      const metadata = JSON.stringify({
        role: role || "participant",
        side: side || null,
        leagueId: (body.leagueId || "").toString().trim() || null,
        matchId: (body.matchId || "").toString().trim() || null,
        callId: (body.callId || "").toString().trim() || null,
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

      return jsonResponse({
        token: await at.toJwt(),
        url: env.LIVEKIT_URL,
        roomName,
        role,
        kind,
      });
    }

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

      const action = (body.action || "").toString().trim();
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
          return jsonResponse({
            ok: true,
            action,
            out: await mutePublishedTrack(env, roomName, targetUserId, true),
          });
        }
        if (action === "unmute") {
          return jsonResponse({
            ok: true,
            action,
            out: await mutePublishedTrack(env, roomName, targetUserId, false),
          });
        }
        return jsonResponse({ error: "Unsupported action" }, 400);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    if (url.pathname === "/flutterwave/verify" && request.method === "POST") {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse({ error: verified.error }, verified.status || 401);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      try {
        const out = await _verifyMasterLeaguePayment(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    if (url.pathname === "/organizer-pro/activate" && request.method === "POST") {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse({ error: verified.error }, verified.status || 401);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      try {
        const out = await _activateOrganizerPro(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    if (url.pathname === "/premium/activate" && request.method === "POST") {
      let verified;
      try {
        verified = await _verifyFirebaseIdToken(env, request);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
      if (!verified.ok) {
        return jsonResponse({ error: verified.error }, verified.status || 401);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      try {
        const out = await _activatePremium(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        return jsonResponse({ error: e.message || String(e) }, 500);
      }
    }

    return textResponse("Not found", 404);
  },
};
