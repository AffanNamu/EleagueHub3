import { AccessToken } from "livekit-server-sdk";

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

  const res = await fetch(
    `${env.LIVEKIT_URL}/twirp/livekit.RoomService/MutePublishedTrack`,
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
    if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
      return new Response(JSON.stringify({ error: "Worker missing LiveKit env vars" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }

    const url = new URL(request.url);

    // ---- ROUTE: POST /  -> issue token ----
    if (url.pathname === "/" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "Invalid JSON" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const userId = (body.userId || "").toString().trim();
      const role = (body.role || "participant").toString().trim(); // "host" | "participant"

      if (!leagueId || !userId) {
        return new Response(JSON.stringify({ error: "leagueId and userId required" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const roomName = `league_${leagueId}`;

      const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
        identity: userId,
        ttl: "2h",
      });

      // Twitter Spaces-style behavior:
      // - listener vs speaker is NOT a different token
      // - everyone can publish audio immediately (client keeps listeners muted)
      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,
        canPublish: true,
        roomAdmin: role === "host",
      });

      const token = await at.toJwt();

      return new Response(JSON.stringify({ token, url: env.LIVEKIT_URL, roomName, role }), {
        headers: { "content-type": "application/json" },
      });
    }

    // ---- ROUTE: POST /admin  -> moderation helper (mute/unmute only) ----
    if (url.pathname === "/admin" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(JSON.stringify({ error: "Invalid JSON" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const action = (body.action || "").toString().trim(); // mute|unmute
      const targetUserId = (body.targetUserId || "").toString().trim();

      if (!leagueId || !action || !targetUserId) {
        return new Response(JSON.stringify({ error: "leagueId, action, targetUserId required" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const roomName = `league_${leagueId}`;

      try {
        if (action === "mute") {
          const out = await mutePublishedTrack(env, roomName, targetUserId, true);
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "unmute") {
          const out = await mutePublishedTrack(env, roomName, targetUserId, false);
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        return new Response(JSON.stringify({ error: "Unsupported action" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message || String(e) }), {
          status: 500,
          headers: { "content-type": "application/json" },
        });
      }
    }

    return new Response("Not found", { status: 404 });
  },
};
