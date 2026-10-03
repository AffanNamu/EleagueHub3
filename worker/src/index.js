//worker/src/index.js
import { AccessToken } from "livekit-server-sdk";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
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

const B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_LOOKUP = new Uint8Array(256).fill(255);
for (let i = 0; i < B64_CHARS.length; i++) {
  B64_LOOKUP[B64_CHARS.charCodeAt(i)] = i;
}
B64_LOOKUP["=".charCodeAt(0)] = 0;

function _safeBase64Decode(input) {
  const str = String(input || "").trim();
  if (!str) return new Uint8Array(0);

  let b64 = str.replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (b64.length % 4)) % 4;
  b64 += "=".repeat(padLen);
  b64 = b64.replace(/[^A-Za-z0-9+/=]/g, "");

  const len = b64.length;
  const padChars = b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0;
  const outLen = (len * 3) / 4 - padChars;
  const out = new Uint8Array(outLen);

  let j = 0;
  for (let i = 0; i < len; i += 4) {
    const a = B64_LOOKUP[b64.charCodeAt(i)];
    const b = B64_LOOKUP[b64.charCodeAt(i + 1)];
    const c = B64_LOOKUP[b64.charCodeAt(i + 2)];
    const d = B64_LOOKUP[b64.charCodeAt(i + 3)];
    if (a === 255 || b === 255) continue;
    if (j < outLen) out[j++] = (a << 2) | (b >> 4);
    if (j < outLen) out[j++] = ((b & 0x0f) << 4) | (c >> 2);
    if (j < outLen) out[j++] = ((c & 0x03) << 6) | d;
  }

  return out;
}

function _b64UrlToUint8Array(b64url) {
  return _safeBase64Decode(b64url);
}

function _uint8ArrayToB64Url(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let result = "";
  for (let i = 0; i < u8.length; i += 3) {
    const a = u8[i];
    const b = i + 1 < u8.length ? u8[i + 1] : 0;
    const c = i + 2 < u8.length ? u8[i + 2] : 0;
    result += B64_CHARS[(a >> 2) & 0x3f];
    result += B64_CHARS[((a & 0x03) << 4) | ((b >> 4) & 0x0f)];
    if (i + 1 < u8.length) {
      result += B64_CHARS[((b & 0x0f) << 2) | ((c >> 6) & 0x03)];
    }
    if (i + 2 < u8.length) {
      result += B64_CHARS[c & 0x3f];
    }
  }
  return result.replace(/\+/g, "-").replace(/\//g, "_");
}

function _utf8ToB64Url(s) {
  return _uint8ArrayToB64Url(new TextEncoder().encode(String(s || "")));
}

function _pemToDerBytes(pem) {
  const raw = String(pem || "").trim();
  if (!raw) throw new Error("Empty PEM input");

  const lines = raw
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("-----"));

  const b64 = lines.join("").replace(/\s+/g, "");
  if (!b64) throw new Error("No base64 content found in PEM");

  const bytes = _safeBase64Decode(b64);
  if (bytes.length === 0) throw new Error("PEM decoded to empty bytes");

  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function _readAsn1Length(bytes, offset) {
  if (offset >= bytes.length) throw new Error("ASN.1: unexpected end reading length");
  const first = bytes[offset];
  if (first < 0x80) {
    return { length: first, bytesRead: 1 };
  }
  const numLenBytes = first & 0x7f;
  if (numLenBytes === 0) throw new Error("ASN.1: indefinite length not supported");
  if (numLenBytes > 4) throw new Error("ASN.1: length too large");
  let len = 0;
  for (let i = 0; i < numLenBytes; i++) {
    if (offset + 1 + i >= bytes.length) throw new Error("ASN.1: unexpected end in length bytes");
    len = (len << 8) | bytes[offset + 1 + i];
  }
  return { length: len, bytesRead: 1 + numLenBytes };
}

function _extractExactPkcs8Der(derBuffer) {
  const bytes = new Uint8Array(derBuffer);
  if (bytes.length < 4) return derBuffer;
  if (bytes[0] !== 0x30) return derBuffer;

  const { length: seqLen, bytesRead } = _readAsn1Length(bytes, 1);
  const totalValidLen = 1 + bytesRead + seqLen;

  if (totalValidLen >= bytes.length) return derBuffer;

  const clean = bytes.slice(0, totalValidLen);
  return clean.buffer.slice(clean.byteOffset, clean.byteOffset + clean.byteLength);
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
  const raw = String(token || "").trim();
  const parts = raw.split(".");
  if (parts.length !== 3) throw new Error("Invalid JWT format: expected 3 parts, got " + parts.length);

  const headerBytes = _b64UrlToUint8Array(parts[0]);
  const payloadBytes = _b64UrlToUint8Array(parts[1]);

  if (headerBytes.length === 0) throw new Error("JWT header decoded to empty");
  if (payloadBytes.length === 0) throw new Error("JWT payload decoded to empty");

  const headerJson = new TextDecoder().decode(headerBytes);
  const payloadJson = new TextDecoder().decode(payloadBytes);

  let header, payload;
  try {
    header = JSON.parse(headerJson);
  } catch (e) {
    throw new Error("JWT header is not valid JSON: " + e.message);
  }
  try {
    payload = JSON.parse(payloadJson);
  } catch (e) {
    throw new Error("JWT payload is not valid JSON: " + e.message);
  }

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

  const dotCount = (token.match(/\./g) || []).length;
  if (dotCount !== 2) {
    return {
      ok: false,
      status: 401,
      error: "Invalid token format: not a valid JWT",
    };
  }

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
  const rawDer = _pemToDerBytes(pem);
  const cleanDer = _extractExactPkcs8Der(rawDer);

  const key = await crypto.subtle.importKey(
    "pkcs8",
    cleanDer,
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
    // FIXED: androidpublisher scope added so this same cached
    // service-account token can also call the Play Developer API to
    // verify Google Play purchases (see
    // _verifyGooglePlaySubscriptionV2 below). Requires this service
    // account to be linked in Play Console -> Setup -> API access,
    // with view/manage permission for orders & subscriptions on this
    // app -- that link is a manual Play Console step, not something
    // this code can do.
    //
    // firebase.messaging added for the Football Hub live-score poller
    // (_pollLiveFixturesAndNotify) to send FCM pushes directly -- the
    // same service account already does this in production via
    // supabase/functions/follow-notify/index.ts, so it's proven to have
    // FCM send permission already (no extra console linking needed,
    // unlike androidpublisher above).
    scope:
      "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/androidpublisher https://www.googleapis.com/auth/firebase.messaging",
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

// Collection-group query: "find every doc named `collectionId` anywhere in
// the database where `fieldPath` == `value`" -- used to find which users
// follow a given football team (users/{uid}/football_followed_teams/{id})
// without needing a reverse-index collection. Requires a matching
// COLLECTION_GROUP index in firestore.indexes.json (see
// "football_followed_teams" entry there); Firestore rejects the query
// with a clear error (surfaced via the thrown Error) if that index is
// ever missing or still building.
async function _firestoreQueryCollectionGroupEquals(env, collectionId, fieldPath, stringValue) {
  const accessToken = await _serviceAccountAccessToken(env);
  const res = await fetch(`${_firestoreRestBase(env)}:runQuery`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId, allDescendants: true }],
        where: {
          fieldFilter: {
            field: { fieldPath },
            op: "EQUAL",
            value: { stringValue },
          },
        },
        limit: 1000,
      },
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Firestore collection-group query (${collectionId}.${fieldPath}=${stringValue}) failed (${res.status}): ${txt}`);
  }
  const rows = await res.json();
  // Each doc's resource name looks like:
  // projects/P/databases/(default)/documents/users/{uid}/football_followed_teams/{teamId}
  // -- the uid is the path segment right after "users".
  const uids = new Set();
  for (const row of Array.isArray(rows) ? rows : []) {
    const name = row && row.document && row.document.name;
    if (!name) continue;
    const parts = String(name).split("/");
    const idx = parts.indexOf("users");
    if (idx >= 0 && parts[idx + 1]) uids.add(parts[idx + 1]);
  }
  return Array.from(uids);
}

// ── FCM push (mirrors supabase/functions/follow-notify/index.ts's proven
// production pattern exactly: fetch tokens from users/{uid}/fcmTokens,
// send one FCM HTTP v1 message per token, delete any token FCM reports as
// unregistered so it's never retried again). ──────────────────────────────

async function _fetchFcmTokensForUid(env, uid) {
  const accessToken = await _serviceAccountAccessToken(env);
  const url = `${_firestoreRestBase(env)}/users/${encodeURIComponent(uid)}/fcmTokens?pageSize=100`;
  const res = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  if (res.status === 404) return [];
  if (!res.ok) return [];

  const data = await res.json();
  const tokens = new Set();
  for (const doc of (data && data.documents) || []) {
    const t = ((doc.fields && doc.fields.token && doc.fields.token.stringValue) || "").trim();
    if (t) tokens.add(t);
  }
  return Array.from(tokens);
}

async function _deleteFcmToken(env, uid, token) {
  try {
    const accessToken = await _serviceAccountAccessToken(env);
    const url = `${_firestoreRestBase(env)}/users/${encodeURIComponent(uid)}/fcmTokens/${encodeURIComponent(token)}`;
    await fetch(url, { method: "DELETE", headers: { authorization: `Bearer ${accessToken}` } });
  } catch (_e) {
    // Best-effort cleanup only.
  }
}

// Sends one push to every device registered for `uid`. Never throws --
// a notification failure must never take down the caller (the live-score
// poller may be mid-way through notifying many followers of many events).
async function _sendFcmToUid(env, uid, { title, body, data, androidChannelId }) {
  const projectId = _requireEnvString(env, "FIREBASE_PROJECT_ID");
  let tokens;
  try {
    tokens = await _fetchFcmTokensForUid(env, uid);
  } catch (_e) {
    return { sent: 0 };
  }
  if (tokens.length === 0) return { sent: 0 };

  const accessToken = await _serviceAccountAccessToken(env);
  const dataStrings = {};
  for (const [k, v] of Object.entries(data || {})) dataStrings[k] = String(v);

  let sent = 0;
  await Promise.all(
    tokens.map(async (token) => {
      try {
        const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
          method: "POST",
          headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body },
              data: dataStrings,
              android: {
                priority: "high",
                notification: { channel_id: androidChannelId || "football_hub_channel", sound: "default" },
              },
              apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
            },
          }),
        });
        if (res.ok) {
          sent += 1;
          return;
        }
        const txt = await res.text();
        if (res.status === 404 || txt.includes("UNREGISTERED")) {
          await _deleteFcmToken(env, uid, token);
        }
      } catch (_e) {
        // Best-effort -- one bad token/device must never stop the others.
      }
    })
  );
  return { sent };
}

function _moneyEqWithinTolerance(expected, actual, currency) {
  const c = String(currency || "").trim().toUpperCase();
  if (typeof expected !== "number" || typeof actual !== "number") return false;
  if (c === "NGN") return Math.abs(expected - actual) <= 1.0;
  return Math.abs(expected - actual) <= 0.02;
}

function _isValidPlanId(planId) {
  return ["basic", "pro", "elite"].includes(String(planId || "").trim().toLowerCase());
}

function _isValidDurationId(durationId) {
  return ["1mo", "3mo", "6mo", "yearly"].includes(String(durationId || "").trim().toLowerCase());
}

function _durationDays(durationId) {
  const d = String(durationId || "").trim().toLowerCase();
  if (d === "1mo") return 30;
  if (d === "3mo") return 90;
  if (d === "6mo") return 180;
  if (d === "yearly") return 365;
  return 0;
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

// ─────────────────────────────────────────────────────────────────────────
// GOOGLE PLAY BILLING VERIFICATION
// ─────────────────────────────────────────────────────────────────────────
//
// NEW: this section lets Google Play Billing purchases activate through
// the EXACT SAME organizerPro/organizerProPlan custom-claims path that
// Flutterwave already uses successfully. Previously, Google Play
// purchases only ever wrote the Firestore /users profile directly from
// the client, and master_leagues creation depended entirely on
// firestore.rules' profileHasActivePlan() fallback to authorize the
// write from that profile data. That fallback was never actually
// confirmed working end-to-end in production. Custom claims are: web
// has used them successfully every time. Routing Google Play through
// the same claims path removes the untested code path entirely instead
// of continuing to debug it.

const GOOGLE_PLAY_ACTIVE_SUBSCRIPTION_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
]);

// IMPORTANT: these keys MUST exactly match the Play Console subscription
// (base plan) product IDs the app actually purchases -- i.e. whatever
// GooglePlayBillingCatalog.subscriptionIdForPlan() resolves to on the
// client (lib/core/services/payments/google_play_billing_catalog.dart).
// The keys below are that file's --dart-define DEFAULTS
// (GPB_SUB_PRO_3MO_ID, GPB_SUB_PRO_6MO_ID, etc). If your GitHub Actions
// build passes different --dart-define overrides for any of those, this
// table needs to be updated to match, or genuine purchases will be
// rejected as "Unrecognized Google Play product".
const GOOGLE_PLAY_PRODUCT_TO_PLAN = {
  pro_1mo: { plan: "pro", duration: "1mo" },
  pro_3mo: { plan: "pro", duration: "3mo" },
  pro_6mo: { plan: "pro", duration: "6mo" },
  pro_yearly: { plan: "pro", duration: "yearly" },
  elite_1mo: { plan: "elite", duration: "1mo" },
  elite_3mo: { plan: "elite", duration: "3mo" },
  elite_6mo: { plan: "elite", duration: "6mo" },
  elite_yearly: { plan: "elite", duration: "yearly" },
};

// Verifies a subscription purchase via the Play Developer API's current
// (non-deprecated) subscriptionsv2 endpoint. Requires:
//   - env.ANDROID_PACKAGE_NAME set to the app's applicationId.
//   - The service account behind FIREBASE_CLIENT_EMAIL/
//     FIREBASE_PRIVATE_KEY linked in Play Console -> Setup -> API
//     access, with permission to view orders & subscriptions for this
//     app. (Manual Play Console step -- not something this code does.)
async function _verifyGooglePlaySubscriptionV2(env, packageName, purchaseToken) {
  const accessToken = await _serviceAccountAccessToken(env);
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(
    packageName
  )}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

  const res = await fetch(url, {
    method: "GET",
    headers: { authorization: `Bearer ${accessToken}` },
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Google Play subscription verify failed (${res.status}): ${txt}`);
  }

  return res.json();
}

async function _activateOrganizerProGooglePlay(env, uid, requestedPlan, requestedDuration, purchaseToken) {
  const packageName = _requireEnvString(env, "ANDROID_PACKAGE_NAME");

  let purchase;
  try {
    purchase = await _verifyGooglePlaySubscriptionV2(env, packageName, purchaseToken);
  } catch (e) {
    return {
      ok: false,
      status: 502,
      error: "Could not verify Google Play purchase: " + (e.message || String(e)),
    };
  }

  const state = String(purchase.subscriptionState || "").trim();
  if (!GOOGLE_PLAY_ACTIVE_SUBSCRIPTION_STATES.has(state)) {
    return {
      ok: false,
      status: 403,
      error: `Google Play subscription is not active (state=${state || "unknown"}).`,
    };
  }

  const lineItems = Array.isArray(purchase.lineItems) ? purchase.lineItems : [];
  if (lineItems.length === 0) {
    return { ok: false, status: 403, error: "Google Play purchase has no line items." };
  }

  const purchasedProductId = String(lineItems[0].productId || "").trim();
  const resolved = GOOGLE_PLAY_PRODUCT_TO_PLAN[purchasedProductId];
  if (!resolved) {
    return {
      ok: false,
      status: 403,
      error: `Unrecognized Google Play product "${purchasedProductId}". This purchase could not be matched to a known plan.`,
    };
  }

  // Google's verified purchase is authoritative -- NOT the client's
  // claimed plan/duration. A client could in principle send any
  // `plan`/`duration` it likes in the request body; only what Google
  // confirms was actually bought gets activated.
  if (resolved.plan !== requestedPlan || resolved.duration !== requestedDuration) {
    return {
      ok: false,
      status: 409,
      error:
        `This purchase is for ${resolved.plan} (${resolved.duration}), ` +
        `not the requested ${requestedPlan} (${requestedDuration}).`,
    };
  }

  const expiryTimeRaw = lineItems[0].expiryTime;
  const expiryMs = expiryTimeRaw ? Date.parse(expiryTimeRaw) : NaN;
  if (!Number.isFinite(expiryMs) || expiryMs <= Date.now()) {
    return { ok: false, status: 403, error: "Google Play subscription has no valid future expiry." };
  }

  const nowMs = Date.now();
  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: resolved.plan,
    organizerProDuration: resolved.duration,
    organizerProExpiryMs: expiryMs,
  };

  await _setFirebaseCustomClaims(env, uid, nextClaims);

  await _firestorePatchDoc(env, `users/${uid}`, {
    activePlanId: resolved.plan,
    activePlanDurationId: resolved.duration,
    planPurchasedAtMs: nowMs,
    planExpiresAtMs: expiryMs,
    planReceiptId: purchaseToken,
    planProvider: "google_play_billing",
    updatedAt: nowMs,
  });

  await _firestorePatchDoc(env, `users/${uid}/entitlements/master_league`, {
    active: true,
    plan: resolved.plan,
    duration: resolved.duration,
    provider: "google_play_billing",
    receiptId: purchaseToken,
    transactionId: String(purchase.latestOrderId || ""),
    currency: "",
    amount: 0,
    activatedAtMs: nowMs,
    expiresAtMs: expiryMs,
    updatedAtMs: nowMs,
  });

  return {
    ok: true,
    status: 200,
    success: true,
    uid,
    plan: resolved.plan,
    duration: resolved.duration,
    expiryMs,
    provider: "google_play_billing",
    receiptId: purchaseToken,
    transactionId: String(purchase.latestOrderId || ""),
    currency: "",
    amount: 0,
  };
}

// ── App Store (iOS) subscription verification ──────────────────────────────
//
// The Flutter client's in_app_purchase_storekit plugin sends the base64
// App Store receipt as `purchaseToken` (PurchaseDetails.verificationData
// .serverVerificationData — this plugin still uses the classic StoreKit1
// Payment Queue transaction model, not StoreKit2, so this is the whole
// receipt blob, not a signed JWS transaction). That's why this uses
// Apple's verifyReceipt endpoint (App-Specific Shared Secret) rather than
// the newer App Store Server API (which takes a transaction ID + ES256 JWT
// signed with an In-App Purchase API key) — matches what's actually being
// sent. If a future plugin upgrade switches to StoreKit2/JWS transactions,
// this needs to change to the transaction-ID + JWT approach instead.
//
// Requires env.APPLE_SHARED_SECRET — App Store Connect → your app →
// Subscriptions → "App-Specific Shared Secret".

const APPLE_PRODUCT_TO_PLAN = {
  pro_1mo: { plan: "pro", duration: "1mo" },
  pro_3mo: { plan: "pro", duration: "3mo" },
  pro_6mo: { plan: "pro", duration: "6mo" },
  pro_yearly: { plan: "pro", duration: "yearly" },
  elite_1mo: { plan: "elite", duration: "1mo" },
  elite_3mo: { plan: "elite", duration: "3mo" },
  elite_6mo: { plan: "elite", duration: "6mo" },
  elite_yearly: { plan: "elite", duration: "yearly" },
};

async function _callAppleVerifyReceipt(url, receiptBase64, sharedSecret) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      "receipt-data": receiptBase64,
      password: sharedSecret,
      "exclude-old-transactions": true,
    }),
  });
  if (!res.ok) {
    throw new Error(`Apple verifyReceipt HTTP error (${res.status})`);
  }
  return res.json();
}

// Verifies a base64 App Store receipt against Apple's verifyReceipt
// endpoint (production first, falling back to sandbox on status 21007 —
// "this receipt is from the test environment" — Apple's own documented
// pattern for handling TestFlight/sandbox receipts sent to production).
// Returns the single most recent purchase entry across the receipt's
// subscription renewal history (or in-app purchase list as a fallback).
async function _verifyAppStoreReceipt(env, receiptBase64) {
  const sharedSecret = _requireEnvString(env, "APPLE_SHARED_SECRET");
  const receipt = String(receiptBase64 || "").trim();
  if (!receipt) throw new Error("Missing App Store receipt data");

  let json = await _callAppleVerifyReceipt(
    "https://buy.itunes.apple.com/verifyReceipt",
    receipt,
    sharedSecret
  );

  if (Number(json.status) === 21007) {
    json = await _callAppleVerifyReceipt(
      "https://sandbox.itunes.apple.com/verifyReceipt",
      receipt,
      sharedSecret
    );
  }

  if (Number(json.status) !== 0) {
    throw new Error(`Apple verifyReceipt rejected the receipt (status=${json.status})`);
  }

  // latest_receipt_info is authoritative for auto-renewable subscriptions
  // (full renewal history); receipt.in_app is the fallback for older/non-
  // subscription receipt shapes. Either way, take the entry with the
  // latest expires_date_ms — that's the current subscription period.
  const entries = Array.isArray(json.latest_receipt_info) && json.latest_receipt_info.length > 0
    ? json.latest_receipt_info
    : (Array.isArray(json.receipt && json.receipt.in_app) ? json.receipt.in_app : []);

  if (entries.length === 0) {
    throw new Error("Apple receipt contains no purchase entries.");
  }

  entries.sort((a, b) => Number(a.expires_date_ms || 0) - Number(b.expires_date_ms || 0));
  const latest = entries[entries.length - 1];

  return {
    productId: String(latest.product_id || "").trim(),
    transactionId: String(latest.transaction_id || "").trim(),
    // NEW: needed to link this subscription to the signed-in uid (see
    // apple_transactions/{originalTransactionId} below) so that a later,
    // unauthenticated App Store Server Notification for the SAME
    // subscription (renewal, refund, etc.) can be resolved back to a user
    // -- ASN notifications never carry a Firebase uid or ID token.
    originalTransactionId: String(latest.original_transaction_id || "").trim(),
    expiresMs: Number(latest.expires_date_ms || 0),
    // Present only if Apple/App Store support revoked or refunded this
    // specific transaction -- must never be treated as active if set.
    cancelledMs: latest.cancellation_date_ms ? Number(latest.cancellation_date_ms) : 0,
  };
}

async function _activateOrganizerProAppStore(env, uid, requestedPlan, requestedDuration, receiptBase64) {
  let purchase;
  try {
    purchase = await _verifyAppStoreReceipt(env, receiptBase64);
  } catch (e) {
    return {
      ok: false,
      status: 502,
      error: "Could not verify App Store purchase: " + (e.message || String(e)),
    };
  }

  if (purchase.cancelledMs > 0) {
    return { ok: false, status: 403, error: "This App Store purchase was refunded or revoked." };
  }

  const resolved = APPLE_PRODUCT_TO_PLAN[purchase.productId];
  if (!resolved) {
    return {
      ok: false,
      status: 403,
      error: `Unrecognized App Store product "${purchase.productId}". This purchase could not be matched to a known plan.`,
    };
  }

  // Apple's verified purchase is authoritative -- NOT the client's claimed
  // plan/duration. Mirrors the same check on the Google Play branch above.
  if (resolved.plan !== requestedPlan || resolved.duration !== requestedDuration) {
    return {
      ok: false,
      status: 409,
      error:
        `This purchase is for ${resolved.plan} (${resolved.duration}), ` +
        `not the requested ${requestedPlan} (${requestedDuration}).`,
    };
  }

  if (!(purchase.expiresMs > Date.now())) {
    return { ok: false, status: 403, error: "App Store subscription has no valid future expiry." };
  }

  const nowMs = Date.now();
  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: resolved.plan,
    organizerProDuration: resolved.duration,
    organizerProExpiryMs: purchase.expiresMs,
  };

  await _setFirebaseCustomClaims(env, uid, nextClaims);

  await _firestorePatchDoc(env, `users/${uid}`, {
    activePlanId: resolved.plan,
    activePlanDurationId: resolved.duration,
    planPurchasedAtMs: nowMs,
    planExpiresAtMs: purchase.expiresMs,
    planReceiptId: purchase.transactionId,
    planProvider: "app_store",
    updatedAt: nowMs,
  });

  await _firestorePatchDoc(env, `users/${uid}/entitlements/master_league`, {
    active: true,
    plan: resolved.plan,
    duration: resolved.duration,
    provider: "app_store",
    receiptId: purchase.transactionId,
    transactionId: purchase.transactionId,
    currency: "",
    amount: 0,
    activatedAtMs: nowMs,
    expiresAtMs: purchase.expiresMs,
    updatedAtMs: nowMs,
  });

  // NEW: link this Apple subscription to the eSportlyic user who just
  // purchased it. App Store Server Notifications (renewals, refunds,
  // grace periods, ...) arrive later with no Firebase ID token and no
  // uid at all -- only originalTransactionId -- so this is the ONLY
  // place that mapping can be safely established (we have a
  // Firebase-authenticated uid here; ASN handlers never do). Best-effort:
  // a failure here must not fail the purchase the user is actively
  // waiting on.
  if (purchase.originalTransactionId) {
    try {
      await _firestorePatchDoc(env, `apple_transactions/${purchase.originalTransactionId}`, {
        uid,
        productId: purchase.productId,
        updatedAtMs: nowMs,
      });
    } catch (e) {
      console.error(
        `[appstore] Failed to link originalTransactionId=${purchase.originalTransactionId} to uid=${uid}: ${e.message || String(e)}`
      );
    }
  }

  return {
    ok: true,
    status: 200,
    success: true,
    uid,
    plan: resolved.plan,
    duration: resolved.duration,
    expiryMs: purchase.expiresMs,
    provider: "app_store",
    receiptId: purchase.transactionId,
    transactionId: purchase.transactionId,
    currency: "",
    amount: 0,
  };
}

// ── App Store Server Notifications V2 ───────────────────────────────────
//
// Apple posts a signed JWS (`{ signedPayload: "..." }`) to this Worker
// directly, server-to-server, whenever a subscription's state changes
// (renewal, refund, billing failure, grace period, ...) -- independent of
// whether the app is even open. Unlike every other route in this file,
// there is no Firebase ID token here: Apple authenticates itself by
// cryptographically signing the payload, so "verify the signature" IS the
// authentication step.
//
// We deliberately do NOT use Apple's official `@apple/app-store-server-library`
// npm package here. It was tried and it does not work in Cloudflare
// Workers: one of its transitive dependencies (`jsrsasign`) performs
// asynchronous I/O at MODULE LOAD time, which Workers hard-forbids outside
// a request handler ("Disallowed operation called within global scope";
// confirmed with `wrangler dev` -- this crashes the ENTIRE Worker, not just
// this route, since Workers fail to start at all if any top-level import
// throws). Both the JWS chain-verification and the JWS signature
// verification below are hand-rolled instead, using only Web Crypto
// (`crypto.subtle`) and manual ASN.1 DER parsing (reusing the same
// `_readAsn1Length`/`_safeBase64Decode` primitives already used above for
// Firebase's own cert verification) -- these run fine inside a request
// handler. The algorithm mirrors Apple's own official library exactly
// (github.com/apple/app-store-server-library-node's `jws_verification.ts`):
// verify x5c[0] (leaf) was signed by x5c[1] (intermediate), verify x5c[1]
// was signed by a TRUSTED ROOT WE PIN OURSELVES (never x5c[2] -- a sender
// could put anything there), check the intermediate has CA:true and both
// certs carry Apple's private extended-key-usage marker OIDs, check
// certificate validity windows, then verify the outer JWS's ES256
// signature using the now-trusted leaf public key. Validated during
// development against the real Apple Root CA G3 / WWDR G6 intermediate /
// production ECC signing certificate chain published in Apple's own
// app-store-server-library-node test suite.
//
// NOT implemented: OCSP revocation checking (Apple's "enableOnlineChecks").
// This is a real, disclosed scope reduction -- it means a cert that's
// still time-valid but has been revoked by Apple mid-lifetime would still
// pass. Apple's own library treats `enableOnlineChecks: false` as a
// supported mode (used for offline/deterministic verification), so this
// matches a documented degraded mode, not a silent gap.

// Apple Root CA - G3, DER-encoded, base64. Sourced from Apple's own
// official open-source app-store-server-library-node test suite
// (REAL_APPLE_ROOT_BASE64_ENCODED in tests/unit-tests/jws_verification.test.ts)
// -- this is the actual production root, not a mock. This is the ONLY
// trust anchor; nothing received over the wire is ever trusted as a root.
const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

// The Apple App Store bundle identifier for this app (matches
// ios/Runner.xcodeproj's PRODUCT_BUNDLE_IDENTIFIER / the Android
// applicationId -- this app happens to use the same string on both
// platforms). Hardcoded like APPLE_PRODUCT_TO_PLAN above rather than an
// env var, since it's a fixed property of this specific app, not
// per-environment config.
const APPLE_BUNDLE_ID = "com.eleaguehub.app";

// NOTE: `valueStart`/`end` are offsets into the `bytes` array that was
// PASSED IN, not into the returned `raw`/`value` (which are fresh,
// zero-indexed copies). `raw` is the whole TLV (tag+length+value) --
// used when recursing into a nested structure starting fresh at pos=0.
// `value` is just the content bytes, already correctly sliced from
// `bytes` -- use this whenever the value bytes themselves are needed
// (an OID, a BIT STRING's content, a time string, ...), never
// `someTlv.raw.slice(someTlv.valueStart, someTlv.end)` (that double-
// applies the offset, since `raw` is already re-based to start at `pos`).
function _appleReadTlv(bytes, pos) {
  const tag = bytes[pos];
  const { length, bytesRead } = _readAsn1Length(bytes, pos + 1);
  const valueStart = pos + 1 + bytesRead;
  const end = valueStart + length;
  return { tag, valueStart, end, raw: bytes.slice(pos, end), value: bytes.slice(valueStart, end) };
}

function _appleOidBytesToDotted(oidBytes) {
  const parts = [];
  const first = oidBytes[0];
  parts.push(Math.floor(first / 40));
  parts.push(first % 40);
  let val = 0;
  for (let i = 1; i < oidBytes.length; i++) {
    val = (val << 7) | (oidBytes[i] & 0x7f);
    if ((oidBytes[i] & 0x80) === 0) {
      parts.push(val);
      val = 0;
    }
  }
  return parts.join(".");
}

// signatureAlgorithm OID -> WebCrypto hash name (Apple's whole chain is
// ECDSA -- no other algorithm is accepted).
const _APPLE_SIG_OID_TO_HASH = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
  "1.2.840.10045.4.3.4": "SHA-512",
};

// EC namedCurve OID (from a SubjectPublicKeyInfo's AlgorithmIdentifier
// parameters) -> WebCrypto curve name.
const _APPLE_CURVE_OID_TO_NAME = {
  "1.2.840.10045.3.1.7": "P-256",
  "1.3.132.0.34": "P-384",
  "1.3.132.0.35": "P-521",
};

function _appleCurveComponentLen(curveName) {
  if (curveName === "P-256") return 32;
  if (curveName === "P-384") return 48;
  if (curveName === "P-521") return 66;
  throw new Error("Unsupported EC curve: " + curveName);
}

function _appleEcCurveFromSpki(spkiRaw) {
  // SubjectPublicKeyInfo ::= SEQUENCE { algorithm AlgorithmIdentifier, subjectPublicKey BIT STRING }
  // AlgorithmIdentifier (for an EC key) ::= SEQUENCE { OID ecPublicKey, OID namedCurve }
  const outer = _appleReadTlv(spkiRaw, 0);
  const algSeq = _appleReadTlv(spkiRaw, outer.valueStart);
  const algInner = _appleReadTlv(algSeq.raw, 0);
  const algOid = _appleReadTlv(algSeq.raw, algInner.valueStart);
  const curveOid = _appleReadTlv(algSeq.raw, algOid.end);
  const curveOidDotted = _appleOidBytesToDotted(algSeq.raw.slice(curveOid.valueStart, curveOid.end));
  const curveName = _APPLE_CURVE_OID_TO_NAME[curveOidDotted];
  if (!curveName) throw new Error("Unsupported EC curve OID: " + curveOidDotted);
  return curveName;
}

// DER SEQUENCE{ INTEGER r, INTEGER s } -> raw r||s, fixed-width per curve
// (WebCrypto's ECDSA verify expects raw r||s per the JOSE/WebCrypto spec,
// never the ASN.1 DER form X.509 certificate signatures are stored in).
function _appleDerEcdsaSigToRawRS(derSig, compLen) {
  const seq = _appleReadTlv(derSig, 0);
  const rTlv = _appleReadTlv(derSig, seq.valueStart);
  const sTlv = _appleReadTlv(derSig, rTlv.end);

  function intToFixed(tlv) {
    let bytes = tlv.value;
    while (bytes.length > compLen && bytes[0] === 0x00) bytes = bytes.slice(1);
    if (bytes.length > compLen) throw new Error("ECDSA signature integer too large for curve");
    const out = new Uint8Array(compLen);
    out.set(bytes, compLen - bytes.length);
    return out;
  }

  const r = intToFixed(rTlv);
  const s = intToFixed(sTlv);
  const out = new Uint8Array(compLen * 2);
  out.set(r, 0);
  out.set(s, compLen);
  return out;
}

// Parses one DER X.509 certificate into exactly the fields the chain
// verifier needs. Structure per RFC 5280; mirrors the working, tested
// walker already used by _extractSpkiFromX509Der above, extended to also
// read validity dates, issuer/subject raw bytes (for byte-exact identity
// comparison instead of formatting distinguished-name strings), the outer
// signatureAlgorithm + signatureValue, and extension OIDs / BasicConstraints.
function _appleParseCertificate(certDer) {
  const bytes = certDer instanceof Uint8Array ? certDer : new Uint8Array(certDer);

  // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
  const outer = _appleReadTlv(bytes, 0);
  const tbs = _appleReadTlv(bytes, outer.valueStart); // raw TLV incl. header -- this exact byte range is what's signed
  const sigAlgTlv = _appleReadTlv(bytes, tbs.end);
  const sigValueTlv = _appleReadTlv(bytes, sigAlgTlv.end); // BIT STRING
  // BIT STRING's first content byte is the "unused bits" count (always 0 for DER signatures)
  const sigBytes = bytes.slice(sigValueTlv.valueStart + 1, sigValueTlv.end);

  const sigAlgSeq = _appleReadTlv(sigAlgTlv.raw, 0);
  const sigAlgOidTlv = _appleReadTlv(sigAlgTlv.raw, sigAlgSeq.valueStart);
  const sigAlgOid = _appleOidBytesToDotted(sigAlgTlv.raw.slice(sigAlgOidTlv.valueStart, sigAlgOidTlv.end));

  // Walk tbsCertificate's fields.
  const tbsSeq = _appleReadTlv(tbs.raw, 0);
  let p = tbsSeq.valueStart;
  if (tbs.raw[p] === 0xa0) {
    const version = _appleReadTlv(tbs.raw, p);
    p = version.end;
  }
  const serial = _appleReadTlv(tbs.raw, p); p = serial.end;
  const tbsSigAlg = _appleReadTlv(tbs.raw, p); p = tbsSigAlg.end;
  const issuer = _appleReadTlv(tbs.raw, p); p = issuer.end;
  const validity = _appleReadTlv(tbs.raw, p); p = validity.end;
  const subject = _appleReadTlv(tbs.raw, p); p = subject.end;
  const spki = _appleReadTlv(tbs.raw, p); p = spki.end;

  let extensionsTlv = null;
  while (p < tbs.raw.length) {
    const tlv = _appleReadTlv(tbs.raw, p);
    if (tlv.tag === 0xa3) extensionsTlv = tlv; // extensions [3] EXPLICIT
    p = tlv.end;
  }

  const validitySeq = _appleReadTlv(validity.raw, 0);
  const notBeforeTlv = _appleReadTlv(validity.raw, validitySeq.valueStart);
  const notAfterTlv = _appleReadTlv(validity.raw, notBeforeTlv.end);
  const notBefore = _appleParseAsn1Time(notBeforeTlv);
  const notAfter = _appleParseAsn1Time(notAfterTlv);

  const extensionOids = new Set();
  let basicConstraintsCA = false;
  if (extensionsTlv) {
    // extensionsTlv.raw already starts at the [3] tag; unwrap it, then read the inner SEQUENCE OF Extension.
    const wrapper = _appleReadTlv(extensionsTlv.raw, 0);
    const inner = _appleReadTlv(extensionsTlv.raw, wrapper.valueStart);
    let ep = inner.valueStart;
    while (ep < inner.end) {
      const extTlv = _appleReadTlv(extensionsTlv.raw, ep);
      ep = extTlv.end;
      const extSeq = _appleReadTlv(extTlv.raw, 0);
      let xp = extSeq.valueStart;
      const oidTlv = _appleReadTlv(extTlv.raw, xp); xp = oidTlv.end;
      const oidDotted = _appleOidBytesToDotted(extTlv.raw.slice(oidTlv.valueStart, oidTlv.end));
      extensionOids.add(oidDotted);
      if (extTlv.raw[xp] === 0x01) {
        const boolTlv = _appleReadTlv(extTlv.raw, xp);
        xp = boolTlv.end;
      }
      const valueTlv = _appleReadTlv(extTlv.raw, xp); // extnValue OCTET STRING
      if (oidDotted === "2.5.29.19") {
        const octetContent = extTlv.raw.slice(valueTlv.valueStart, valueTlv.end);
        if (octetContent.length > 2) {
          const bcSeq = _appleReadTlv(octetContent, 0);
          if (octetContent[bcSeq.valueStart] === 0x01) {
            basicConstraintsCA = octetContent[bcSeq.valueStart + 2] !== 0x00;
          }
        }
      }
    }
  }

  return {
    tbsRaw: tbs.raw,
    sigAlgOid,
    sigBytes,
    issuerRaw: issuer.raw,
    subjectRaw: subject.raw,
    spkiRaw: spki.raw,
    notBefore,
    notAfter,
    extensionOids,
    basicConstraintsCA,
  };
}

function _appleParseAsn1Time(tlv) {
  const isUtcTime = tlv.tag === 0x17;
  const str = new TextDecoder().decode(tlv.value);
  let y, mo, d, h, mi, s;
  if (isUtcTime) {
    const yy = parseInt(str.slice(0, 2), 10);
    y = yy < 50 ? 2000 + yy : 1900 + yy;
    mo = str.slice(2, 4); d = str.slice(4, 6); h = str.slice(6, 8); mi = str.slice(8, 10); s = str.slice(10, 12);
  } else {
    y = parseInt(str.slice(0, 4), 10);
    mo = str.slice(4, 6); d = str.slice(6, 8); h = str.slice(8, 10); mi = str.slice(10, 12); s = str.slice(12, 14);
  }
  return new Date(Date.UTC(y, parseInt(mo, 10) - 1, parseInt(d, 10), parseInt(h, 10), parseInt(mi, 10), parseInt(s, 10)));
}

function _appleBytesEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

async function _appleImportEcPublicKey(spkiRaw, curveName) {
  return crypto.subtle.importKey("spki", spkiRaw, { name: "ECDSA", namedCurve: curveName }, false, ["verify"]);
}

// Verifies `subjectCert` was signed by `issuerCert`'s public key (curve
// and hash auto-detected from each cert -- Apple's root/intermediate use
// P-384/SHA-384, its leaf signing certs use P-256/SHA-256).
async function _appleVerifyCertSignedBy(subjectCert, issuerCert) {
  const hashName = _APPLE_SIG_OID_TO_HASH[subjectCert.sigAlgOid];
  if (!hashName) throw new Error("Unsupported certificate signature algorithm OID: " + subjectCert.sigAlgOid);
  const curveName = _appleEcCurveFromSpki(issuerCert.spkiRaw);
  const compLen = _appleCurveComponentLen(curveName);
  const rawSig = _appleDerEcdsaSigToRawRS(subjectCert.sigBytes, compLen);
  const issuerKey = await _appleImportEcPublicKey(issuerCert.spkiRaw, curveName);
  return crypto.subtle.verify({ name: "ECDSA", hash: hashName }, issuerKey, rawSig, subjectCert.tbsRaw);
}

function _appleCheckCertDates(cert, effectiveDate, skewMs) {
  const t = effectiveDate.getTime();
  return cert.notBefore.getTime() <= t + skewMs && cert.notAfter.getTime() >= t - skewMs;
}

// Verifies the x5c certificate chain from a JWS header and returns the
// leaf certificate's raw SubjectPublicKeyInfo (used to verify the JWS's
// own signature). Mirrors Apple's official app-store-server-library-node
// `verifyCertificateChainWithoutCaching` (see the large comment above).
async function _appleVerifyCertChainAndGetLeafSpki(x5cBase64Array, effectiveDate) {
  if (!Array.isArray(x5cBase64Array) || x5cBase64Array.length !== 3) {
    throw new Error(
      `Invalid x5c chain length: expected 3, got ${Array.isArray(x5cBase64Array) ? x5cBase64Array.length : 0}`
    );
  }

  const leaf = _appleParseCertificate(_safeBase64Decode(x5cBase64Array[0]));
  const intermediate = _appleParseCertificate(_safeBase64Decode(x5cBase64Array[1]));
  // x5c[2] (whatever "root" the sender included) is intentionally IGNORED
  // for trust purposes -- trust is anchored ONLY to APPLE_ROOT_CA_G3_BASE64,
  // pinned in this file, never to anything a peer sent us.
  const pinnedRoot = _appleParseCertificate(_safeBase64Decode(APPLE_ROOT_CA_G3_BASE64));

  if (!_appleBytesEqual(intermediate.issuerRaw, pinnedRoot.subjectRaw)) {
    throw new Error("Intermediate certificate was not issued by the pinned Apple root");
  }
  if (!(await _appleVerifyCertSignedBy(intermediate, pinnedRoot))) {
    throw new Error("Intermediate certificate signature did not verify against the pinned Apple root");
  }
  if (!_appleBytesEqual(leaf.issuerRaw, intermediate.subjectRaw)) {
    throw new Error("Leaf certificate issuer does not match intermediate subject");
  }
  if (!(await _appleVerifyCertSignedBy(leaf, intermediate))) {
    throw new Error("Leaf certificate signature did not verify against the intermediate");
  }
  if (!intermediate.basicConstraintsCA) {
    throw new Error("Intermediate certificate is not marked as a CA");
  }
  // Apple's private extended-key-usage marker OIDs, present on genuine
  // App Store signing certs -- same checks Apple's own library performs.
  if (!leaf.extensionOids.has("1.2.840.113635.100.6.11.1")) {
    throw new Error("Leaf certificate missing Apple App Store signing marker extension");
  }
  if (!intermediate.extensionOids.has("1.2.840.113635.100.6.2.1")) {
    throw new Error("Intermediate certificate missing Apple WWDR marker extension");
  }

  const skewMs = 60000;
  if (!_appleCheckCertDates(leaf, effectiveDate, skewMs)) throw new Error("Leaf certificate is outside its validity window");
  if (!_appleCheckCertDates(intermediate, effectiveDate, skewMs)) throw new Error("Intermediate certificate is outside its validity window");
  if (!_appleCheckCertDates(pinnedRoot, effectiveDate, skewMs)) throw new Error("Pinned root certificate is outside its validity window");

  return leaf.spkiRaw;
}

// Verifies and decodes ONE Apple-signed JWS string. Used for the outer
// App Store Server Notification `signedPayload`, and identically for the
// nested `signedTransactionInfo` / `signedRenewalInfo` blobs inside it --
// all three are independently JWS-signed the same way.
async function _appleVerifyAndDecodeSignedPayload(jws) {
  const parts = String(jws || "").split(".");
  if (parts.length !== 3) throw new Error("Malformed JWS: expected header.payload.signature");

  const header = JSON.parse(new TextDecoder().decode(_safeBase64Decode(parts[0])));
  if (header.alg !== "ES256") throw new Error(`Unsupported/unexpected JWS alg: ${header.alg}`);

  // Peek at the (not-yet-verified) payload only to read its claimed
  // signedDate, used purely to pick an effective date for the
  // certificate validity-window check below -- mirrors Apple's own
  // library, which does the same before verifying the signature. Nothing
  // from this unverified payload is acted upon until AFTER the signature
  // check below succeeds.
  const unverifiedPayload = JSON.parse(new TextDecoder().decode(_safeBase64Decode(parts[1])));
  const effectiveDate = unverifiedPayload.signedDate ? new Date(Number(unverifiedPayload.signedDate)) : new Date();

  const leafSpkiRaw = await _appleVerifyCertChainAndGetLeafSpki(header.x5c, effectiveDate);
  const verifyKey = await crypto.subtle.importKey("spki", leafSpkiRaw, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);

  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const sigBytes = _safeBase64Decode(parts[2]);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, verifyKey, sigBytes, signingInput);
  if (!ok) throw new Error("JWS signature verification failed");

  return unverifiedPayload;
}

async function _appleFindUidForOriginalTransactionId(env, originalTransactionId) {
  const res = await _firestoreGetDocSA(env, `apple_transactions/${originalTransactionId}`);
  if (!res.ok || !res.doc) return "";
  const fields = _fromFirestoreDoc(res.doc);
  return String(fields.uid || "").trim();
}

async function _appleApplyEntitlement(env, uid, plan, duration, expiresAtMs) {
  const nowMs = Date.now();
  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: plan,
    organizerProDuration: duration,
    organizerProExpiryMs: expiresAtMs,
  };
  await _setFirebaseCustomClaims(env, uid, nextClaims);
  await _firestorePatchDoc(env, `users/${uid}`, {
    activePlanId: plan,
    activePlanDurationId: duration,
    planExpiresAtMs: expiresAtMs,
    planProvider: "app_store",
    updatedAt: nowMs,
  });
}

async function _appleRevokeEntitlement(env, uid, reason) {
  const nowMs = Date.now();
  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = { ...currentClaims, organizerPro: false, organizerProExpiryMs: 0 };
  await _setFirebaseCustomClaims(env, uid, nextClaims);
  await _firestorePatchDoc(env, `users/${uid}`, {
    planExpiresAtMs: 0,
    updatedAt: nowMs,
  });
  console.log(`[appstore/notifications] Revoked entitlement for uid=${uid} reason=${reason}`);
}

// The notification-lifecycle state machine. See the large comment at the
// top of this section for why there's no Firebase auth here -- the
// caller (the route handler below) has already verified the JWS signature
// before this runs, so `decoded`'s contents are trustworthy at this point.
async function _appleProcessNotificationEffects(env, decoded, notificationSignedDateMs) {
  const notificationType = String(decoded.notificationType || "").trim();
  const subtype = String(decoded.subtype || "").trim();
  const data = decoded.data || {};

  let transactionInfo = null;
  let renewalInfo = null;
  try {
    if (data.signedTransactionInfo) {
      transactionInfo = await _appleVerifyAndDecodeSignedPayload(data.signedTransactionInfo);
    }
    if (data.signedRenewalInfo) {
      renewalInfo = await _appleVerifyAndDecodeSignedPayload(data.signedRenewalInfo);
    }
  } catch (e) {
    throw new Error(`Nested signed field failed verification: ${e.message || String(e)}`);
  }

  if (!transactionInfo) {
    return { action: "logged-only", reason: "no-transaction-info", notificationType, subtype };
  }

  const originalTransactionId = String(transactionInfo.originalTransactionId || "").trim();
  const productId = String(transactionInfo.productId || "").trim();
  if (!originalTransactionId) {
    return { action: "logged-only", reason: "no-original-transaction-id", notificationType, subtype };
  }

  const uid = await _appleFindUidForOriginalTransactionId(env, originalTransactionId);
  if (!uid) {
    // This subscription has never gone through the pull-based activation
    // flow (_activateOrganizerProAppStore), so we don't yet know which
    // eSportlyic account it belongs to. Never guess -- just park it for
    // later reconciliation once/if the user's own purchase-activation
    // call links it.
    await _firestorePatchDoc(env, `apple_notifications_unlinked/${originalTransactionId}`, {
      lastNotificationType: notificationType,
      lastNotificationSubtype: subtype,
      productId,
      updatedAtMs: Date.now(),
    });
    return { action: "unlinked", originalTransactionId, notificationType, subtype };
  }

  const entPath = `users/${uid}/entitlements/master_league`;
  const existing = await _firestoreGetDocSA(env, entPath);
  const existingFields = existing.ok && existing.doc ? _fromFirestoreDoc(existing.doc) : {};

  // Out-of-order guard: a retried/delayed notification must never undo a
  // newer one. Every JWS carries Apple's own server-stamped `signedDate`;
  // only apply an update if it's at least as new as the last one we
  // actually applied for this specific subscription.
  const lastAppliedSignedDateMs = Number(existingFields.lastNotificationSignedDateMs || 0);
  if (notificationSignedDateMs < lastAppliedSignedDateMs) {
    return { action: "stale-ignored", uid, originalTransactionId, notificationType, subtype };
  }

  const resolved = APPLE_PRODUCT_TO_PLAN[productId];
  const expiresAtMs = Number(transactionInfo.expiresDate || 0);
  const revocationReason = transactionInfo.revocationReason;

  const baseFields = {
    lastNotificationType: notificationType,
    lastNotificationSubtype: subtype,
    lastNotificationSignedDateMs: notificationSignedDateMs,
    environment: String(data.environment || ""),
    transactionId: String(transactionInfo.transactionId || ""),
    provider: "app_store",
    updatedAtMs: Date.now(),
  };

  switch (notificationType) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "RENEWAL_EXTENDED":
    case "RENEWAL_EXTENSION": {
      if (!resolved) return { action: "logged-only", reason: "unrecognized-product", productId, notificationType };
      if (!(expiresAtMs > Date.now())) return { action: "logged-only", reason: "no-future-expiry", notificationType };
      await _appleApplyEntitlement(env, uid, resolved.plan, resolved.duration, expiresAtMs);
      await _firestorePatchDoc(env, entPath, {
        ...baseFields,
        plan: resolved.plan,
        duration: resolved.duration,
        expiresAtMs,
        active: true,
      });
      return { action: "granted", uid, plan: resolved.plan, expiresAtMs, notificationType };
    }

    case "DID_FAIL_TO_RENEW": {
      if (subtype === "GRACE_PERIOD" && renewalInfo && renewalInfo.gracePeriodExpiresDate && resolved) {
        const graceExpiresAtMs = Number(renewalInfo.gracePeriodExpiresDate || 0);
        if (graceExpiresAtMs > Date.now()) {
          await _appleApplyEntitlement(env, uid, resolved.plan, resolved.duration, graceExpiresAtMs);
          await _firestorePatchDoc(env, entPath, {
            ...baseFields,
            plan: resolved.plan,
            duration: resolved.duration,
            expiresAtMs: graceExpiresAtMs,
            active: true,
          });
          return { action: "grace-period", uid, graceExpiresAtMs, notificationType };
        }
      }
      await _firestorePatchDoc(env, entPath, baseFields);
      return { action: "logged-only", notificationType, subtype };
    }

    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED": {
      await _appleRevokeEntitlement(env, uid, notificationType);
      await _firestorePatchDoc(env, entPath, { ...baseFields, active: false });
      return { action: "expired", uid, notificationType };
    }

    case "REFUND":
    case "REVOKE": {
      const reasonStr = `${notificationType}:${revocationReason ?? ""}`;
      await _appleRevokeEntitlement(env, uid, reasonStr);
      await _firestorePatchDoc(env, entPath, {
        ...baseFields,
        active: false,
        revocationReason: String(revocationReason ?? ""),
      });
      return { action: "revoked", uid, notificationType };
    }

    case "DID_CHANGE_RENEWAL_STATUS":
    case "DID_CHANGE_RENEWAL_PREF": {
      const metaFields = { ...baseFields };
      if (renewalInfo) {
        metaFields.autoRenewStatus = !!renewalInfo.autoRenewStatus;
        metaFields.autoRenewProductId = String(renewalInfo.autoRenewProductId || "");
      }
      await _firestorePatchDoc(env, entPath, metaFields);
      return { action: "metadata-updated", uid, notificationType };
    }

    // Informational / no entitlement change.
    case "REFUND_DECLINED":
    case "PRICE_INCREASE":
    case "CONSUMPTION_REQUEST":
      await _firestorePatchDoc(env, entPath, baseFields);
      return { action: "logged-only", notificationType, subtype };

    default:
      // Unknown/future notification type: never throw -- just record it.
      await _firestorePatchDoc(env, entPath, baseFields);
      return { action: "logged-only", notificationType, subtype, unrecognized: true };
  }
}

// Entry point for the /appstore/notifications route. Returns
// { status, body } for the caller to send as the HTTP response.
//
// Response code policy (per Apple's docs): 200 for "handled" AND for
// "already processed" / "can't link to a user yet" -- we don't want
// Apple's retry-with-backoff for cases that aren't going to change on
// retry. Non-200 only for genuine transient failures, so Apple's own
// retry (up to ~24h) does the retrying for us.
async function _appleHandleServerNotification(env, requestBodyText) {
  let signedPayload;
  try {
    const parsed = JSON.parse(requestBodyText);
    signedPayload = String(parsed.signedPayload || "").trim();
  } catch (e) {
    return { status: 400, body: { error: "Invalid JSON body" } };
  }
  if (!signedPayload) return { status: 400, body: { error: "Missing signedPayload" } };

  let decoded;
  try {
    decoded = await _appleVerifyAndDecodeSignedPayload(signedPayload);
  } catch (e) {
    console.error("[appstore/notifications] JWS verification failed:", e.message || String(e));
    return { status: 400, body: { error: "Signature verification failed" } };
  }

  const notificationUUID = String(decoded.notificationUUID || "").trim();
  const notificationType = String(decoded.notificationType || "").trim();
  const subtype = String(decoded.subtype || "").trim();
  const data = decoded.data || {};
  const bundleId = String(data.bundleId || "").trim();
  const environment = String(data.environment || "").trim();
  const signedDateMs = Number(decoded.signedDate || 0);

  console.log(
    `[appstore/notifications] type=${notificationType} subtype=${subtype} uuid=${notificationUUID} env=${environment} bundleId=${bundleId}`
  );

  if (bundleId && bundleId !== APPLE_BUNDLE_ID) {
    console.error(`[appstore/notifications] Bundle ID mismatch: got "${bundleId}", expected "${APPLE_BUNDLE_ID}"`);
    // Not our app -- acknowledge so Apple doesn't retry, but do nothing.
    return { status: 200, body: { ok: true, skipped: "bundle-id-mismatch" } };
  }

  if (!notificationUUID) {
    console.error("[appstore/notifications] Missing notificationUUID; acking without processing.");
    return { status: 200, body: { ok: true, skipped: "missing-notification-uuid" } };
  }

  // Idempotency: Apple retries notifications. `notificationUUID` is
  // Apple's own dedupe key for this exact delivery. If we've already
  // fully processed it, just re-acknowledge -- do NOT redo the effects.
  // (The effects below are themselves idempotent and guarded by the
  // out-of-order signedDate check above, which is the actual safety net;
  // this ledger is purely an optimization to skip redundant work on
  // ordinary retries, following the same GET-then-write pattern already
  // used elsewhere in this file, e.g. _verifyMasterLeaguePayment.)
  const ledgerPath = `apple_notifications/${notificationUUID}`;
  const existingLedger = await _firestoreGetDocSA(env, ledgerPath);
  if (existingLedger.ok && existingLedger.doc) {
    return { status: 200, body: { ok: true, alreadyProcessed: true } };
  }

  let outcome;
  try {
    outcome = await _appleProcessNotificationEffects(env, decoded, signedDateMs);
  } catch (e) {
    console.error("[appstore/notifications] Failed to process notification effects:", e.message || String(e));
    // Transient/unexpected failure -- return non-200 so Apple retries.
    return { status: 500, body: { error: "Internal processing error" } };
  }

  try {
    await _firestoreCreateDocSA(env, ledgerPath, {
      notificationType,
      subtype,
      environment,
      outcomeAction: String(outcome.action || ""),
      processedAtMs: Date.now(),
    });
  } catch (e) {
    // The effects already applied successfully; a failure to write the
    // ledger just means a future retry might redo (harmlessly idempotent)
    // work. Not worth failing the whole request over.
    console.error("[appstore/notifications] Failed to write idempotency ledger:", e.message || String(e));
  }

  return { status: 200, body: { ok: true, ...outcome } };
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
      // Fallback only — used when app_config/pricing is unreachable or
      // doesn't have this field set. Real values are set via the
      // esportlyic-admin Pricing Settings page (Master League Plan Fees
      // section), which writes straight to app_config/pricing.ngn.*.
      proPlan1moFee: 2000,
      proPlan3moFee: 5000,
      proPlan6moFee: 9000,
      proPlanYearlyFee: 15000,
      elitePlan1moFee: 4000,
      elitePlan3moFee: 10000,
      elitePlan6moFee: 18000,
      elitePlanYearlyFee: 30000,
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
      // Fallback only — see the ngn.proPlan1moFee note above.
      proPlan1moFee: 4.0,
      proPlan3moFee: 10.0,
      proPlan6moFee: 18.0,
      proPlanYearlyFee: 30.0,
      elitePlan1moFee: 8.0,
      elitePlan3moFee: 20.0,
      elitePlan6moFee: 36.0,
      elitePlanYearlyFee: 60.0,
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
      proPlan1moFee: raw.proPlan1moFee ?? dft.proPlan1moFee,
      proPlan3moFee: raw.proPlan3moFee ?? dft.proPlan3moFee,
      proPlan6moFee: raw.proPlan6moFee ?? dft.proPlan6moFee,
      proPlanYearlyFee: raw.proPlanYearlyFee ?? dft.proPlanYearlyFee,
      elitePlan1moFee: raw.elitePlan1moFee ?? dft.elitePlan1moFee,
      elitePlan3moFee: raw.elitePlan3moFee ?? dft.elitePlan3moFee,
      elitePlan6moFee: raw.elitePlan6moFee ?? dft.elitePlan6moFee,
      elitePlanYearlyFee: raw.elitePlanYearlyFee ?? dft.elitePlanYearlyFee,
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

function _planSubscriptionExpectedFee(planCfg, planId, durationId) {
  const p = String(planId || "").trim().toLowerCase();
  const d = String(durationId || "").trim().toLowerCase();

  if (p === "pro") {
    if (d === "1mo") return Number(planCfg.proPlan1moFee || 0);
    if (d === "3mo") return Number(planCfg.proPlan3moFee || 0);
    if (d === "6mo") return Number(planCfg.proPlan6moFee || 0);
    if (d === "yearly") return Number(planCfg.proPlanYearlyFee || 0);
  }

  if (p === "elite") {
    if (d === "1mo") return Number(planCfg.elitePlan1moFee || 0);
    if (d === "3mo") return Number(planCfg.elitePlan3moFee || 0);
    if (d === "6mo") return Number(planCfg.elitePlan6moFee || 0);
    if (d === "yearly") return Number(planCfg.elitePlanYearlyFee || 0);
  }

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
  if (firebaseEmail && flwEmail && firebaseEmail !== flwEmail) {
    console.warn(
      `[email-mismatch] firebase=${firebaseEmail} flw=${flwEmail} uid=${verified.uid} attempt=${attemptId} tx=${transactionId}`
    );
  }

  if (txRefFromClient && verify.txRef && txRefFromClient !== verify.txRef) {
    return { ok: false, status: 403, error: "txRef mismatch." };
  }

  const attemptProductType = String(attempt.productType || "").trim();
  const attemptProductSubType = String(attempt.productSubType || "").trim();
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

  if (attemptProductType === "plan_subscription") {
    const planId = String(attempt.planId || attemptMeta.plan || "").trim().toLowerCase();
    const durationId = String(attempt.planDurationId || attemptMeta.duration || "").trim().toLowerCase();
    const expected = _planSubscriptionExpectedFee(cfg, planId, durationId);

    if (!_isValidPlanId(planId) || planId === "basic") {
      return { ok: false, status: 403, error: "Invalid paid plan." };
    }
    if (!_isValidDurationId(durationId)) {
      return { ok: false, status: 403, error: "Invalid plan duration." };
    }
    if (!(expected > 0)) {
      return { ok: false, status: 403, error: "Plan subscription pricing is not configured." };
    }
    if (!_moneyEqWithinTolerance(expected, Number(verify.amount || 0), verify.currency)) {
      return {
        ok: false,
        status: 403,
        error: `Plan subscription amount mismatch. Expected ${expected} ${verify.currency}, got ${verify.amount}.`,
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
    productSubType: attemptProductSubType,
    metadata: attempt.metadata && typeof attempt.metadata === "object" ? attempt.metadata : {},
    paidAtMs,
    createdAtMs: paidAtMs,
    updatedAtMs: paidAtMs,
    firebaseEmail: firebaseEmail,
    flutterwaveEmail: flwEmail,
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
  const duration = String(body.duration || "").trim().toLowerCase();
  const provider = String(body.provider || "").trim().toLowerCase();
  const receiptId = String(body.receiptId || "").trim();
  // NEW: the Google Play purchase token OR (NEW) the base64 App Store
  // receipt, required to verify with the relevant store's server API.
  const purchaseToken = String(body.purchaseToken || "").trim();
  const isGooglePlay = provider === "google_play_billing" || provider === "google_play";
  const isAppStore = provider === "app_store" || provider === "apple";

  if (!uid) return { ok: false, status: 401, error: "Unauthenticated." };
  if (!["basic", "pro", "elite"].includes(plan)) {
    return { ok: false, status: 400, error: "Invalid plan." };
  }
  if (plan !== "basic" && !_isValidDurationId(duration)) {
    return { ok: false, status: 400, error: "Invalid duration." };
  }
  // FIXED: this previously only accepted "flutterwave" or "free" here,
  // which meant ANY Google Play activation attempt through this
  // endpoint was rejected outright with "Unsupported provider." Now
  // that Google Play AND App Store are first-class supported providers
  // (see _activateOrganizerProGooglePlay / _activateOrganizerProAppStore
  // below), all variants are accepted. Guideline 3.1.1 requires iOS
  // purchases go through StoreKit -- this must never fall back to
  // Flutterwave for an "app_store" provider.
  if (!["flutterwave", "free", "google_play_billing", "google_play", "app_store", "apple"].includes(provider)) {
    return { ok: false, status: 400, error: "Unsupported provider." };
  }
  if (plan !== "basic" && !isGooglePlay && !isAppStore && !receiptId) {
    return { ok: false, status: 400, error: "receiptId is required." };
  }
  if (plan !== "basic" && isGooglePlay && !purchaseToken) {
    return { ok: false, status: 400, error: "purchaseToken is required." };
  }
  if (plan !== "basic" && isAppStore && !purchaseToken) {
    return { ok: false, status: 400, error: "purchaseToken (App Store receipt) is required." };
  }

  if (plan === "basic") {
    const nowMs = Date.now();
    const currentClaims = await _lookupExistingCustomClaims(env, uid);
    const nextClaims = {
      ...currentClaims,
      organizerPro: true,
      organizerProPlan: "basic",
      organizerProDuration: "3mo",
      organizerProExpiryMs: 0,
    };

    await _setFirebaseCustomClaims(env, uid, nextClaims);

    await _firestorePatchDoc(env, `users/${uid}`, {
      activePlanId: "basic",
      activePlanDurationId: "3mo",
      planPurchasedAtMs: nowMs,
      planExpiresAtMs: 0,
      planReceiptId: "free_basic",
      planProvider: "free",
      updatedAt: nowMs,
    });

    await _firestorePatchDoc(env, `users/${uid}/entitlements/master_league`, {
      active: true,
      plan: "basic",
      duration: "3mo",
      provider: "free",
      receiptId: "free_basic",
      transactionId: "",
      currency: "",
      amount: 0,
      activatedAtMs: nowMs,
      expiresAtMs: 0,
      updatedAtMs: nowMs,
    });

    return {
      ok: true,
      status: 200,
      success: true,
      uid,
      plan: "basic",
      duration: "3mo",
      expiryMs: 0,
      provider: "free",
      receiptId: "free_basic",
      transactionId: "",
      currency: "",
      amount: 0,
    };
  }

  // ── NEW: Google Play Billing branch — verifies with the Play
  // Developer API and grants the SAME custom claims Flutterwave does.
  if (isGooglePlay) {
    return await _activateOrganizerProGooglePlay(env, uid, plan, duration, purchaseToken);
  }

  // ── NEW: App Store branch — verifies with Apple's verifyReceipt and
  // grants the SAME custom claims the other two providers do.
  if (isAppStore) {
    return await _activateOrganizerProAppStore(env, uid, plan, duration, purchaseToken);
  }

  // ── Flutterwave branch (unchanged) ────────────────────────────────────
  let txId = "";
  let verify = null;
  let currency = "";
  let amount = 0;

  txId = receiptId.startsWith("FLW-") ? receiptId.slice(4).trim() : receiptId;
  if (!txId) {
    return { ok: false, status: 400, error: "Invalid receiptId." };
  }

  verify = await _verifyFlutterwaveTransaction(env, txId);
  currency = verify.currency;
  amount = Number(verify.amount || 0);

  const pricing = await _readPricingConfig(env);
  const cfg = _pricingForCurrency(pricing, currency);

  if (!cfg.paymentsEnabled) {
    return { ok: false, status: 403, error: "Payments are currently disabled." };
  }
  if (!cfg.flutterwaveEnabled) {
    return { ok: false, status: 403, error: "Flutterwave is currently disabled." };
  }

  const expected = _planSubscriptionExpectedFee(cfg, plan, duration);
  if (!(expected > 0)) {
    return { ok: false, status: 403, error: "Organizer Pro pricing is not configured." };
  }

  if (!_moneyEqWithinTolerance(expected, amount, currency)) {
    return {
      ok: false,
      status: 403,
      error: `Amount mismatch. Expected ${expected} ${currency}, got ${amount}.`,
    };
  }

  const nowMs = Date.now();
  const expiryMs = nowMs + _durationDays(duration) * 24 * 60 * 60 * 1000;

  const currentClaims = await _lookupExistingCustomClaims(env, uid);
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: plan,
    organizerProDuration: duration,
    organizerProExpiryMs: expiryMs,
  };

  await _setFirebaseCustomClaims(env, uid, nextClaims);

  await _firestorePatchDoc(env, `users/${uid}`, {
    activePlanId: plan,
    activePlanDurationId: duration,
    planPurchasedAtMs: nowMs,
    planExpiresAtMs: expiryMs,
    planReceiptId: receiptId,
    planProvider: "flutterwave",
    updatedAt: nowMs,
  });

  await _firestorePatchDoc(env, `users/${uid}/entitlements/master_league`, {
    active: true,
    plan,
    duration,
    provider: "flutterwave",
    receiptId,
    transactionId: verify.txId,
    currency,
    amount,
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
    duration,
    expiryMs,
    provider: "flutterwave",
    receiptId,
    transactionId: verify.txId,
    currency,
    amount,
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

// ── Cloudinary signed upload for match highlights ───────────────────────
//
// The Flutter client (cloudinary_signed_video_upload_service.dart) uploads
// highlight clips straight to Cloudinary, which requires a per-upload
// signature -- we never ship the Cloudinary API secret to the client.
// This mirrors exactly the authorization chain firestore.rules already
// enforces for creating a users/leagues/.../highlights doc
// (highlightUploaderIsLeagueParticipant / highlightCreateIsValid), since a
// Cloudinary upload happens entirely outside Firestore and bypasses those
// rules -- so this endpoint has to independently re-derive and check the
// same facts before it will sign anything:
//   1. caller is a real Firebase user (ID token)
//   2. caller has a leagues/{leagueId}/memberships/{uid} doc with a teamId
//      -- NEVER trust a client-supplied teamId, always re-derive it here,
//      exactly like the rules' get(memPath).data.get('teamId', '') does.
//   3. leagues/{leagueId}/matches/{matchId} is finished
//      (matchIsFinished in firestore.rules: isPlayed==true OR
//      status=='FINISHED' OR matchStatus=='FINISHED')
//   4. that teamId is the match's homeTeamId or awayTeamId
//      (isParticipantTeam in firestore.rules)
// Only then do we sign, and only for the exact folder/public_id shape
// firestore.rules' highlightFieldsAreValid will later accept
// (match_highlights/{leagueId}/{matchId}/{teamId} / {highlightId}).

function _highlightMatchIsFinished(matchDocData) {
  const d = matchDocData || {};
  return d.isPlayed === true || d.status === "FINISHED" || d.matchStatus === "FINISHED";
}

function _highlightIsParticipantTeam(matchDocData, teamId) {
  const d = matchDocData || {};
  return d.homeTeamId === teamId || d.awayTeamId === teamId;
}

// Mirrors firestore.rules' canManageLeague()/isOwner()/isOrganizerByMembership():
// a league owner/organizer can act on the league (here: upload a highlight
// for either team) even without being personally assigned to one.
async function _highlightUploaderCanManageLeague(env, leagueId, uid) {
  const leagueRes = await _firestoreGetDocSA(env, `leagues/${leagueId}`);
  if (leagueRes.ok && leagueRes.doc) {
    const l = _fromFirestoreDoc(leagueRes.doc);
    const owners = [l.organizerUid, l.ownerUid, l.organizerUserId, l.ownerId].map((v) =>
      String(v || "").trim()
    );
    if (owners.includes(uid)) return true;
  }
  const memRes = await _firestoreGetDocSA(env, `leagues/${leagueId}/memberships/${uid}`);
  if (memRes.ok && memRes.doc) {
    const role = _fromFirestoreDoc(memRes.doc).role;
    if (role === 0) return true; // LeagueRole.organizer
  }
  return false;
}

async function _sha1Hex(input) {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-1", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Matches _isSafeHighlightsFolder in cloudinary_signed_video_upload_service.dart:
// exactly 4 segments, match_highlights/{leagueId}/{matchId}/{teamId}.
function _parseHighlightFolder(folder) {
  const f = String(folder || "").trim();
  if (!f.startsWith("match_highlights/") || f.includes("..") || f.includes("\\")) return null;
  const parts = f.split("/").filter((p) => p.trim().length > 0);
  if (parts.length !== 4) return null;
  return { leagueId: parts[1], matchId: parts[2], teamId: parts[3] };
}

// Request shape matches cloudinary_signed_video_upload_service.dart's
// _signParams exactly: { "params": { timestamp, folder, public_id, overwrite } }.
// The client computes folder/public_id itself (it needs them for the
// upload regardless of who signs), so this endpoint's job is to
// INDEPENDENTLY VERIFY the teamId embedded in that folder actually belongs
// to the caller -- never just trust it -- before signing.
async function _signHighlightUpload(env, verified, body) {
  const uid = String(verified.uid || "").trim();
  if (!uid) return { ok: false, status: 401, error: "Unauthenticated." };

  const params = (body || {}).params;
  if (!params || typeof params !== "object") {
    return { ok: false, status: 400, error: "Missing params." };
  }

  const parsed = _parseHighlightFolder(params.folder);
  if (!parsed) {
    return {
      ok: false,
      status: 400,
      error: "Invalid folder. Expected match_highlights/{leagueId}/{matchId}/{teamId}.",
    };
  }
  const { leagueId, matchId, teamId: claimedTeamId } = parsed;

  const highlightId = String(params.public_id || "").trim();
  if (!highlightId || highlightId.includes("/") || highlightId.includes("..") || highlightId.includes("\\")) {
    return { ok: false, status: 400, error: "Invalid public_id." };
  }

  const memRes = await _firestoreGetDocSA(env, `leagues/${leagueId}/memberships/${uid}`);
  let actualTeamId = memRes.ok && memRes.doc ? String(_fromFirestoreDoc(memRes.doc).teamId || "").trim() : "";

  if (!actualTeamId) {
    // Not a team member (or no membership at all -- an organizer isn't
    // required to join their own league as a player). League owners can
    // still upload; the client already asked them which team (home/away)
    // this highlight is for, embedded in the claimed folder. That choice
    // is still verified below against the match's real home/away teams,
    // same as the team-member path.
    const canManage = await _highlightUploaderCanManageLeague(env, leagueId, uid);
    if (canManage) {
      actualTeamId = claimedTeamId;
    }
  }

  if (!actualTeamId) {
    return { ok: false, status: 403, error: "You are not a member of this league." };
  }
  // Never trust the client-supplied folder's teamId segment on its own --
  // it must match what we just resolved server-side for this uid.
  if (actualTeamId !== claimedTeamId) {
    return { ok: false, status: 403, error: "Folder does not match your team." };
  }

  const matchRes = await _firestoreGetDocSA(env, `leagues/${leagueId}/matches/${matchId}`);
  if (!matchRes.ok || !matchRes.doc) {
    return { ok: false, status: 404, error: "Match not found." };
  }
  const matchData = _fromFirestoreDoc(matchRes.doc);

  if (!_highlightMatchIsFinished(matchData)) {
    return { ok: false, status: 403, error: "Highlights can only be uploaded for finished matches." };
  }
  if (!_highlightIsParticipantTeam(matchData, actualTeamId)) {
    return { ok: false, status: 403, error: "Your team did not play in this match." };
  }

  const apiKey = _requireEnvString(env, "CLOUDINARY_API_KEY");
  const apiSecret = _requireEnvString(env, "CLOUDINARY_API_SECRET");
  const cloudName = _requireEnvString(env, "CLOUDINARY_CLOUD_NAME");

  // Fresh server timestamp -- the client blindly uses whatever timestamp
  // we return (it does not reuse its own candidate value), so it's safe
  // (and simpler) to mint our own here rather than trust theirs.
  const timestamp = Math.floor(Date.now() / 1000);
  const folder = `match_highlights/${leagueId}/${matchId}/${actualTeamId}`;

  // Cloudinary's classic signing algorithm: alphabetize every parameter
  // that will actually be sent in the upload (excluding file/cloud_name/
  // resource_type/api_key/signature), join as key=value pairs, append the
  // API secret directly (no separator), SHA-1, hex-encode. MUST exactly
  // match the params the client actually sends in the real multipart
  // upload -- see uploadHighlightVideo's FormData (folder, public_id,
  // overwrite, timestamp only; no unique_filename/use_filename).
  const paramsToSign = { folder, overwrite: "true", public_id: highlightId, timestamp: String(timestamp) };
  const stringToSign =
    Object.keys(paramsToSign)
      .sort()
      .map((k) => `${k}=${paramsToSign[k]}`)
      .join("&") + apiSecret;
  const signature = await _sha1Hex(stringToSign);

  return {
    ok: true,
    status: 200,
    cloudName,
    apiKey,
    timestamp,
    signature,
  };
}

// ── Football data provider abstraction ──────────────────────────────────
//
// Route handlers below never talk to api-football.com directly -- they
// call _footballApiProxyRoute with a logical OPERATION NAME (e.g.
// "fixtures"), and this provider object maps that to the actual upstream
// path/params/auth for whichever provider is currently configured.
// Swapping providers later (the written Football Hub plan explicitly
// requires this to stay possible) means writing a new object with this
// same shape and pointing FOOTBALL_PROVIDER at it -- the /football/*
// routes, their caching, and the Dart client's contract never change.
// Lets the API-Football key be set/rotated from the admin panel
// (Settings -> Football Hub) instead of only via the GitHub Actions
// Worker-deploy secret -- changing it there takes effect within 5 minutes,
// no redeploy needed. A Firestore value wins when set; falls back to the
// env secret (env.API_FOOTBALL_KEY) otherwise, so a deployment that has
// never had one set in the admin panel keeps working unchanged.
let _apiFootballKeyCache = { value: "", fetchedAtMs: 0 };
async function _getApiFootballKey(env) {
  const now = Date.now();
  if (_apiFootballKeyCache.fetchedAtMs && now - _apiFootballKeyCache.fetchedAtMs < 5 * 60 * 1000) {
    return _apiFootballKeyCache.value;
  }
  let fromFirestore = "";
  try {
    const res = await _firestoreGetDocSA(env, "football_config/settings");
    const fields = (res.ok && res.doc && res.doc.fields) || {};
    fromFirestore = (fields.apiFootballKey && fields.apiFootballKey.stringValue) || "";
  } catch (_e) {
    // Firestore read failed -- fall through to the env secret below.
  }
  const value = fromFirestore.trim() || (env.API_FOOTBALL_KEY || "").trim();
  _apiFootballKeyCache = { value, fetchedAtMs: now };
  return value;
}

const API_FOOTBALL_PROVIDER = {
  id: "api-football",
  baseUrl: "https://v3.football.api-sports.io",
  async buildHeaders(env) {
    const key = await _getApiFootballKey(env);
    if (!key) {
      throw new Error(
        "API-Football key not configured. Set it in Settings -> Football Hub, or as the Worker's API_FOOTBALL_KEY secret."
      );
    }
    return { "x-apikey": key };
  },
  // Does this provider consider the response an error? api-football.com
  // returns HTTP 200 even on quota-exceeded/bad-request errors, with
  // details in a non-empty `errors` field instead of a non-2xx status.
  isErrorResponse(httpRes, data) {
    const errors = data && data.errors;
    const hasErrors = errors && (Array.isArray(errors) ? errors.length > 0 : Object.keys(errors).length > 0);
    return !httpRes.ok || hasErrors;
  },
  operations: {
    fixtures: {
      upstreamPath: "/fixtures",
      // date: YYYY-MM-DD for the Matches tab's date-picker row.
      // league+season: a specific competition's fixtures/round.
      // team: a team's fixtures (profile screen, "last 5"/"next match").
      allowedParams: ["id", "date", "league", "season", "team", "round", "next", "last", "status", "live"],
    },
    fixtureEvents: {
      upstreamPath: "/fixtures/events",
      allowedParams: ["fixture"],
    },
    standings: {
      upstreamPath: "/standings",
      allowedParams: ["league", "season", "team"],
    },
    squad: {
      upstreamPath: "/players/squads",
      allowedParams: ["team"],
    },
    player: {
      upstreamPath: "/players",
      allowedParams: ["id", "season", "team"],
    },
    leagues: {
      upstreamPath: "/leagues",
      allowedParams: ["search", "country", "season", "id", "code", "type"],
    },
  },
};

// Swap this one line to change football data provider.
const FOOTBALL_PROVIDER = API_FOOTBALL_PROVIDER;

// Best-effort daily usage counters at football_metrics/{YYYY-MM-DD} --
// "know the cost before the bill becomes a surprise." Deliberately a
// simple read-then-patch (not an atomic transform) using the same
// Firestore helpers already proven elsewhere in this file: a rare
// lost-update under concurrent requests is an acceptable tradeoff given
// the volume this guards (<=100 real upstream calls/day on the free
// tier) and that this is observability only, never correctness-critical.
// Never allowed to affect the real response -- always wrapped in try/catch
// by its caller.
async function _recordFootballMetric(env, field) {
  const day = new Date().toISOString().slice(0, 10);
  const docPath = `football_metrics/${day}`;
  const existing = await _firestoreGetDocSA(env, docPath);
  const existingFields = (existing.ok && existing.doc && existing.doc.fields) || {};
  const currentValue = existingFields[field] ? parseInt(existingFields[field].integerValue || "0", 10) : 0;
  await _firestorePatchDoc(env, docPath, {
    [field]: currentValue + 1,
    provider: FOOTBALL_PROVIDER.id,
    lastUpdatedMs: Date.now(),
  });
}

async function _footballApiProxyRoute(env, request, url, operationName, ttlSeconds) {
  let verified;
  try {
    verified = await _verifyFirebaseIdToken(env, request);
  } catch (e) {
    return jsonResponse({ error: "Auth error: " + (e.message || String(e)) }, 500);
  }
  if (!verified.ok) {
    return jsonResponse({ error: verified.error }, verified.status || 401);
  }

  const operation = FOOTBALL_PROVIDER.operations[operationName];
  if (!operation) {
    return jsonResponse({ error: `Unknown football operation: ${operationName}` }, 500);
  }
  const { upstreamPath, allowedParams } = operation;

  // Only forward whitelisted query params -- never pass the caller's query
  // string through verbatim to the upstream API.
  const forwarded = new URLSearchParams();
  for (const key of allowedParams) {
    const v = url.searchParams.get(key);
    if (v !== null && v.trim() !== "") forwarded.set(key, v.trim());
  }
  const cacheKeyUrl = `https://football-hub-cache.internal/${FOOTBALL_PROVIDER.id}${upstreamPath}?${forwarded.toString()}`;
  const cacheKey = new Request(cacheKeyUrl, { method: "GET" });
  const cache = caches.default;

  const cached = await cache.match(cacheKey);
  if (cached) {
    try {
      await _recordFootballMetric(env, "cacheHits");
    } catch (_e) {
      // Best-effort -- never fail the request over a metrics write.
    }
    return new Response(cached.body, {
      status: cached.status,
      headers: { ...CORS_HEADERS, "content-type": "application/json", "x-cache": "HIT" },
    });
  }

  const upstreamUrl = `${FOOTBALL_PROVIDER.baseUrl}${upstreamPath}?${forwarded.toString()}`;

  let upstreamRes;
  try {
    upstreamRes = await fetch(upstreamUrl, { headers: await FOOTBALL_PROVIDER.buildHeaders(env) });
  } catch (e) {
    try {
      await _recordFootballMetric(env, "providerErrors");
    } catch (_e2) {}
    return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 502);
  }

  let data;
  try {
    data = await upstreamRes.json();
  } catch {
    try {
      await _recordFootballMetric(env, "providerErrors");
    } catch (_e2) {}
    return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 502);
  }

  if (FOOTBALL_PROVIDER.isErrorResponse(upstreamRes, data)) {
    try {
      await _recordFootballMetric(env, "providerErrors");
    } catch (_e2) {}
    return jsonResponse(
      { error: "Football data temporarily unavailable. Please try again.", details: data && data.errors },
      502
    );
  }

  try {
    await _recordFootballMetric(env, "apiRequests");
  } catch (_e) {
    // Best-effort -- never fail the request over a metrics write.
  }

  const responseBody = JSON.stringify(data);
  const response = new Response(responseBody, {
    status: 200,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json",
      "cache-control": `public, max-age=${ttlSeconds}`,
      "x-cache": "MISS",
    },
  });

  // Cache a separate copy (cache.put consumes the body) keyed on our own
  // whitelisted-param URL, not the caller's raw request.
  try {
    await cache.put(
      cacheKey,
      new Response(responseBody, {
        status: 200,
        headers: { "content-type": "application/json", "cache-control": `public, max-age=${ttlSeconds}` },
      })
    );
  } catch (_e) {
    // Best-effort -- a cache-write failure should never fail the request.
  }

  return response;
}

// ── Football Hub: live-score poller + goal/kickoff/full-time notifications ─
//
// Runs on a Cloudflare Cron Trigger (see wrangler.toml's [triggers] and the
// `scheduled` export below), NOT per-request -- this is the one piece of
// Football Hub that costs API-Football quota on a fixed schedule whether or
// not anyone opens the app. One consolidated call (`/fixtures?live=all`)
// covers every live match globally regardless of user count, so the cost
// is purely (polls/day), not (users x matches). A second, variable cost
// (one extra call per goal) only happens for a goal in a match at least
// one user actually follows -- see the followerUids check below -- so it
// scales with real engagement, not with how many matches are live.
//
// State is tracked at football_live_state/{fixtureId} (service-account
// only, like football_metrics) so each poll can diff against what was
// last seen and only notify on an actual change.

function _parseLiveFixtureSummary(raw) {
  const fixture = (raw && raw.fixture) || {};
  const league = (raw && raw.league) || {};
  const teams = (raw && raw.teams) || {};
  const home = teams.home || {};
  const away = teams.away || {};
  const goals = (raw && raw.goals) || {};
  const status = fixture.status || {};

  const toInt = (v) => (typeof v === "number" ? Math.trunc(v) : parseInt(v, 10) || 0);

  return {
    id: toInt(fixture.id),
    statusShort: String(status.short || "").trim(),
    leagueName: String(league.name || "").trim(),
    homeTeamId: toInt(home.id),
    homeTeamName: String(home.name || "").trim(),
    awayTeamId: toInt(away.id),
    awayTeamName: String(away.name || "").trim(),
    homeGoals: goals.home == null ? 0 : toInt(goals.home),
    awayGoals: goals.away == null ? 0 : toInt(goals.away),
  };
}

// Only called for a fixture that just had a goal AND has at least one
// follower -- never for every live match on every poll (see the cost
// comment above). Returns the scoring player's name, or null if the
// provider hasn't attributed it yet (events can lag the score by a few
// seconds) or the lookup fails for any reason.
async function _lookupLatestScorerName(env, fixtureId) {
  try {
    const res = await fetch(`${FOOTBALL_PROVIDER.baseUrl}/fixtures/events?fixture=${fixtureId}`, {
      headers: await FOOTBALL_PROVIDER.buildHeaders(env),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const events = (data && data.response) || [];
    const goals = events.filter((e) => String(e.type || "").toLowerCase() === "goal");
    if (goals.length === 0) return null;
    const last = goals[goals.length - 1];
    const name = (last.player && last.player.name) || "";
    return name.trim() || null;
  } catch (_e) {
    return null;
  }
}

// Plain-text template commentary -- not an LLM call (that's a separate,
// explicitly-costed decision; see this session's AI-daily-summary
// discussion). Matches the written Football Hub plan's own example
// format ("GOAL! Barcelona 2-1 Real Madrid, 67'") plus the scorer's name
// when _lookupLatestScorerName found one in time.
function _buildEventNotification(kind, f, scorerName) {
  const scoreLine = `${f.homeTeamName} ${f.homeGoals}-${f.awayGoals} ${f.awayTeamName}`;
  if (kind === "goal") {
    const who = scorerName ? `${scorerName} scores! ` : "";
    return { title: "⚽ GOAL!", body: `${who}${scoreLine}` };
  }
  if (kind === "kickoff") {
    return { title: `🔴 ${f.homeTeamName} vs ${f.awayTeamName}`, body: "The match has started." };
  }
  if (kind === "fulltime") {
    return { title: "🏁 Full time", body: scoreLine };
  }
  return { title: "Football Hub", body: scoreLine };
}

async function _pollLiveFixturesAndNotify(env) {
  // Admin-controlled kill switch (esportlyic-admin's Settings -> Football
  // Hub page, PATCH /api/admin/football-hub -> football_config/settings).
  // Missing doc/field = enabled, matching the toggle UI's own default.
  // Checked first and before any api-football.com call so pausing the
  // poller also pauses its quota usage, not just its notifications.
  try {
    const configRes = await _firestoreGetDocSA(env, "football_config/settings");
    const fields = (configRes.ok && configRes.doc && configRes.doc.fields) || {};
    const pollerEnabled = fields.pollerEnabled ? fields.pollerEnabled.booleanValue !== false : true;
    if (!pollerEnabled) {
      console.log("[football poll] skipped -- poller disabled via admin panel");
      return;
    }
  } catch (e) {
    // If we can't read the config, fail open (keep polling) rather than
    // silently going dark over a transient Firestore read error.
    console.error("[football poll] config read failed, polling anyway:", e.message || String(e));
  }

  let upstreamRes;
  try {
    upstreamRes = await fetch(`${FOOTBALL_PROVIDER.baseUrl}/fixtures?live=all`, {
      headers: await FOOTBALL_PROVIDER.buildHeaders(env),
    });
  } catch (e) {
    console.error("[football poll] upstream unreachable:", e.message || String(e));
    return;
  }

  let data;
  try {
    data = await upstreamRes.json();
  } catch {
    return;
  }
  if (FOOTBALL_PROVIDER.isErrorResponse(upstreamRes, data)) {
    try {
      await _recordFootballMetric(env, "providerErrors");
    } catch (_e) {}
    console.error("[football poll] provider error:", JSON.stringify(data && data.errors));
    return;
  }
  try {
    await _recordFootballMetric(env, "apiRequests");
  } catch (_e) {}

  const fixtures = ((data && data.response) || []).map(_parseLiveFixtureSummary).filter((f) => f.id > 0);

  for (const f of fixtures) {
    const statePath = `football_live_state/${f.id}`;
    let prevHome = 0;
    let prevAway = 0;
    let prevStatus = "";
    try {
      const prev = await _firestoreGetDocSA(env, statePath);
      const fields = (prev.ok && prev.doc && prev.doc.fields) || {};
      prevHome = fields.homeGoals ? parseInt(fields.homeGoals.integerValue || "0", 10) : 0;
      prevAway = fields.awayGoals ? parseInt(fields.awayGoals.integerValue || "0", 10) : 0;
      prevStatus = fields.statusShort ? fields.statusShort.stringValue || "" : "";
    } catch (_e) {
      // Treat as first-ever sighting of this fixture if the read fails.
    }

    const events = [];
    if (f.homeGoals > prevHome || f.awayGoals > prevAway) events.push("goal");
    if (f.statusShort === "1H" && prevStatus !== "1H" && prevStatus !== "2H" && prevStatus !== "FT") events.push("kickoff");
    if (f.statusShort === "FT" && prevStatus !== "FT") events.push("fulltime");

    try {
      await _firestorePatchDoc(env, statePath, {
        homeGoals: f.homeGoals,
        awayGoals: f.awayGoals,
        statusShort: f.statusShort,
        updatedAtMs: Date.now(),
      });
    } catch (e) {
      console.error(`[football poll] state write failed for fixture ${f.id}:`, e.message || String(e));
    }

    if (events.length === 0) continue;

    let followerUids;
    try {
      const [homeFollowers, awayFollowers] = await Promise.all([
        _firestoreQueryCollectionGroupEquals(env, "football_followed_teams", "teamId", String(f.homeTeamId)),
        _firestoreQueryCollectionGroupEquals(env, "football_followed_teams", "teamId", String(f.awayTeamId)),
      ]);
      followerUids = Array.from(new Set([...homeFollowers, ...awayFollowers]));
    } catch (e) {
      console.error(`[football poll] follower lookup failed for fixture ${f.id}:`, e.message || String(e));
      continue;
    }
    if (followerUids.length === 0) continue;

    for (const kind of events) {
      const scorerName = kind === "goal" ? await _lookupLatestScorerName(env, f.id) : null;
      const { title, body } = _buildEventNotification(kind, f, scorerName);
      const route = `/football/match/${f.id}`;

      await Promise.all(
        followerUids.map((uid) =>
          _sendFcmToUid(env, uid, {
            title,
            body,
            data: { type: `football_${kind}`, route, fixtureId: f.id },
            androidChannelId: "football_hub_channel",
          })
        )
      );
    }
  }
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS } });
    }

    const url = new URL(request.url);

    if (url.pathname === "/" && request.method === "POST") {
      try {
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
      } catch (e) {
        return jsonResponse({ error: "LiveKit token error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/admin" && request.method === "POST") {
      try {
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
        return jsonResponse({ error: "Admin error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/flutterwave/verify" && request.method === "POST") {
      try {
        let verified;
        try {
          verified = await _verifyFirebaseIdToken(env, request);
        } catch (e) {
          return jsonResponse({ error: "Auth error: " + (e.message || String(e)) }, 500);
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

        const out = await _verifyMasterLeaguePayment(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        console.error("[flutterwave/verify] Unhandled:", e.message || String(e), e.stack || "");
        return jsonResponse({ error: "Payment verification error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/organizer-pro/activate" && request.method === "POST") {
      try {
        let verified;
        try {
          verified = await _verifyFirebaseIdToken(env, request);
        } catch (e) {
          return jsonResponse({ error: "Auth error: " + (e.message || String(e)) }, 500);
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

        const out = await _activateOrganizerPro(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        return jsonResponse({ error: "Organizer Pro error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/premium/activate" && request.method === "POST") {
      try {
        let verified;
        try {
          verified = await _verifyFirebaseIdToken(env, request);
        } catch (e) {
          return jsonResponse({ error: "Auth error: " + (e.message || String(e)) }, 500);
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

        const out = await _activatePremium(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        return jsonResponse({ error: "Premium error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/appstore/notifications" && request.method === "POST") {
      // NO Firebase auth check here -- Apple calls this directly,
      // server-to-server. Authentication IS verifying the JWS signature
      // inside _appleHandleServerNotification. Configure the SAME URL as
      // both the "Production Server URL" and "Sandbox Server URL" in App
      // Store Connect -- the decoded payload's own `data.environment`
      // field tells us which one a given notification is from.
      try {
        const rawBody = await request.text();
        const { status, body } = await _appleHandleServerNotification(env, rawBody);
        return jsonResponse(body, status);
      } catch (e) {
        console.error("[appstore/notifications] Unhandled:", e.message || String(e), e.stack || "");
        // Unexpected error -- non-200 so Apple retries.
        return jsonResponse({ error: "Internal error" }, 500);
      }
    }

    if (url.pathname === "/cloudinary/sign-highlight" && request.method === "POST") {
      try {
        let verified;
        try {
          verified = await _verifyFirebaseIdToken(env, request);
        } catch (e) {
          return jsonResponse({ error: "Auth error: " + (e.message || String(e)) }, 500);
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

        const out = await _signHighlightUpload(env, verified, body || {});
        return out.ok
          ? jsonResponse(out, 200)
          : jsonResponse({ error: out.error }, out.status || 400);
      } catch (e) {
        console.error("[cloudinary/sign-highlight] Unhandled:", e.message || String(e), e.stack || "");
        return jsonResponse({ error: "Highlight sign error: " + (e.message || String(e)) }, 500);
      }
    }

    if (url.pathname === "/football/fixtures" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "fixtures", 300); // 5 min -- scores can be live/in-progress.
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    if (url.pathname === "/football/fixture-events" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "fixtureEvents", 60); // 1 min -- goals/cards during a live match.
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    if (url.pathname === "/football/standings" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "standings", 3600); // 1 hour -- standings only change after full-time.
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    if (url.pathname === "/football/squad" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "squad", 86400); // 1 day -- squads change rarely (transfer windows only).
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    if (url.pathname === "/football/player" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "player", 21600); // 6 hours -- season stats update slowly enough for this.
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    if (url.pathname === "/football/leagues" && request.method === "GET") {
      try {
        return await _footballApiProxyRoute(env, request, url, "leagues", 86400); // 1 day -- the league catalog itself rarely changes.
      } catch (e) {
        return jsonResponse({ error: "Football data temporarily unavailable. Please try again." }, 500);
      }
    }

    return jsonResponse({ error: "Not found", path: url.pathname }, 404);
  },

  // Cloudflare Cron Trigger entry point -- see wrangler.toml's [triggers]
  // for the schedule. ctx.waitUntil keeps the invocation alive until the
  // poll finishes without blocking anything else.
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(_pollLiveFixturesAndNotify(env));
  },
};