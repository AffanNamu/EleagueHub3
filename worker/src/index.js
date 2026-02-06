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

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...CORS_HEADERS } });
    }

    if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
      return jsonResponse({ error: "Worker missing LiveKit env vars" }, 500);
    }

    const url = new URL(request.url);

    // ---- ROUTE: POST /  -> issue token ----
    if (url.pathname === "/" && request.method === "POST") {
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

    return textResponse("Not found", 404);
  },
};
