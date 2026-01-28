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

  const matchId = sanitizeRoomTokenPart(body.matchId);
  if (matchId) return `match_${matchId}`;

  const leagueId = sanitizeRoomTokenPart(body.leagueId);
  if (leagueId) return `league_${leagueId}`;

  return "";
}

function toHttpBaseUrl(livekitUrl) {
  const u = String(livekitUrl || "").trim();
  if (!u) return "";

  // LiveKit Cloud commonly uses:
  // - wss://xxxx.livekit.cloud  (client connect)
  // - https://xxxx.livekit.cloud (server APIs)
  if (u.startsWith("wss://")) return "https://" + u.slice("wss://".length);
  if (u.startsWith("ws://")) return "http://" + u.slice("ws://".length);

  // If already https/http, keep it.
  if (u.startsWith("https://") || u.startsWith("http://")) return u;

  // Fallback: assume https
  return `https://${u}`;
}

/**
 * Create an admin JWT that can call LiveKit RoomService APIs.
 * We use roomAdmin: true which is required for MutePublishedTrack.
 */
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

/**
 * Call LiveKit Twirp API: MutePublishedTrack
 */
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

export default {
  async fetch(request, env) {
    // CORS preflight
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
      // - Old clients used leagueId -> roomName: league_<leagueId>
      // - New live video clients use matchId -> roomName: match_<matchId>
      // - Also supports explicit roomName
      if (!roomName) {
        return jsonResponse(
          { error: "One of leagueId, matchId, or roomName is required" },
          400
        );
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const matchId = (body.matchId || "").toString().trim();

      const metadata = JSON.stringify({
        role: role || "participant",
        side: side || null,
        leagueId: leagueId || null,
        matchId: matchId || null,
        kind: matchId ? "match" : "league",
      });

      const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
        identity: userId,
        ttl: "2h",
        metadata,
      });

      // Existing behavior: permissive publish (Spaces-like).
      // The client decides whether to actually enable mic/camera.
      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,
        canPublish: true,
        roomAdmin: role === "host",
      });

      const token = await at.toJwt();

      // Return LIVEKIT_URL exactly as configured (wss://... is correct for clients)
      return jsonResponse({ token, url: env.LIVEKIT_URL, roomName, role });
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
          { error: "One of leagueId, matchId, or roomName is required" },
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

    return textResponse("Not found", 404);
  },
};
