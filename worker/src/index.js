import { AccessToken } from "livekit-server-sdk";

/**
 * Admin JWT for moderation (mute/unmute)
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

async function mutePublishedTrack(env, roomName, identity, muted) {
  const adminJwt = await makeAdminJwt(env, roomName);

  const res = await fetch(
    `${env.LIVEKIT_URL}/twirp/livekit.RoomService/MutePublishedTrack`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${adminJwt}`,
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
      return new Response(JSON.stringify({ error: "Missing LiveKit env vars" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }

    const url = new URL(request.url);

    // ---- ISSUE TOKEN ----
    if (url.pathname === "/" && request.method === "POST") {
      const body = await request.json();

      const leagueId = String(body.leagueId || "").trim();
      const userId = String(body.userId || "").trim();
      const isHost = Boolean(body.isHost);

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

      // 🔥 TWITTER SPACES PERMISSION MODEL
      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublish: true,        // EVERYONE CAN PUBLISH
        canPublishData: true,
        roomAdmin: isHost,       // ONLY LEAGUE ADMIN
      });

      const token = await at.toJwt();

      return new Response(
        JSON.stringify({
          token,
          url: env.LIVEKIT_URL,
          roomName,
        }),
        { headers: { "content-type": "application/json" } }
      );
    }

    // ---- ADMIN ACTIONS ----
    if (url.pathname === "/admin" && request.method === "POST") {
      const body = await request.json();

      const leagueId = String(body.leagueId || "").trim();
      const action = String(body.action || "").trim();
      const targetUserId = String(body.targetUserId || "").trim();

      if (!leagueId || !action || !targetUserId) {
        return new Response(JSON.stringify({ error: "Invalid admin request" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const roomName = `league_${leagueId}`;

      try {
        if (action === "mute") {
          const out = await mutePublishedTrack(env, roomName, targetUserId, true);
          return new Response(JSON.stringify({ ok: true, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "unmute") {
          const out = await mutePublishedTrack(env, roomName, targetUserId, false);
          return new Response(JSON.stringify({ ok: true, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        return new Response(JSON.stringify({ error: "Unknown action" }), {
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
