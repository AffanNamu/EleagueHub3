import { AccessToken } from "livekit-server-sdk";

// LiveKit Server API helpers.
// These endpoints are provided by LiveKit server.
// Docs: https://docs.livekit.io/home/server/api/
async function lkUpdateParticipant(env, roomName, identity, permissions) {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: "worker-admin",
    ttl: "5m",
  });

  // Grant only what's needed to call admin APIs
  at.addGrant({
    room: roomName,
    roomAdmin: true,
  });

  const adminToken = await at.toJwt();

  const res = await fetch(`${env.LIVEKIT_URL}/twirp/livekit.RoomService/UpdateParticipant`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${adminToken}`,
    },
    body: JSON.stringify({
      room: roomName,
      identity,
      permission: permissions,
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`LiveKit UpdateParticipant failed ${res.status}: ${txt}`);
  }

  return res.json();
}

async function lkMuteTrack(env, roomName, identity, muted) {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: "worker-admin",
    ttl: "5m",
  });

  at.addGrant({
    room: roomName,
    roomAdmin: true,
  });

  const adminToken = await at.toJwt();

  const res = await fetch(`${env.LIVEKIT_URL}/twirp/livekit.RoomService/MutePublishedTrack`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${adminToken}`,
    },
    body: JSON.stringify({
      room: roomName,
      identity,
      muted,
      // trackSid optional; if omitted, LiveKit mutes matching published track.
      // Some deployments require trackSid; if so, we can fetch participant info first.
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`LiveKit MutePublishedTrack failed ${res.status}: ${txt}`);
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

    // -------- TOKEN ISSUER (same endpoint) --------
    // POST with { leagueId, userId, role }
    // role: "host" | "listener"
    // Enforcement: listeners get canPublish=false always.
    if (request.method === "POST" && new URL(request.url).pathname === "/") {
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
      const role = (body.role || "listener").toString().trim();

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

      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,

        // Strong enforcement:
        // - host token can publish
        // - listener token cannot publish (approval is done by server API UpdateParticipant)
        canPublish: role === "host",
      });

      const token = await at.toJwt();

      return new Response(
        JSON.stringify({
          token,
          url: env.LIVEKIT_URL,
          roomName,
          role,
        }),
        { headers: { "content-type": "application/json" } }
      );
    }

    // -------- ADMIN ACTIONS --------
    // POST /admin with { leagueId, hostId, action, targetUserId, muted? }
    // action: "approve" | "revoke" | "mute" | "unmute"
    if (request.method === "POST" && new URL(request.url).pathname === "/admin") {
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
      const hostId = (body.hostId || "").toString().trim();
      const action = (body.action || "").toString().trim();
      const targetUserId = (body.targetUserId || "").toString().trim();

      if (!leagueId || !hostId || !action || !targetUserId) {
        return new Response(JSON.stringify({ error: "leagueId, hostId, action, targetUserId required" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      // NOTE: This worker does not verify hostId against Firestore.
      // For real security, add Firebase Admin verification OR signed host JWT.
      // MVP assumes clients are honest. (Still stronger than app-only because LiveKit blocks publish)

      const roomName = `league_${leagueId}`;

      try {
        if (action === "approve") {
          const out = await lkUpdateParticipant(env, roomName, targetUserId, {
            canPublish: true,
            canSubscribe: true,
            canPublishData: true,
            // LiveKit supports granular sources in newer versions.
            // If your server supports it:
            // canPublishSources: ["microphone"]
          });
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "revoke") {
          const out = await lkUpdateParticipant(env, roomName, targetUserId, {
            canPublish: false,
            canSubscribe: true,
            canPublishData: true,
          });
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "mute") {
          const out = await lkMuteTrack(env, roomName, targetUserId, true);
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "unmute") {
          const out = await lkMuteTrack(env, roomName, targetUserId, false);
          return new Response(JSON.stringify({ ok: true, action, out }), {
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
// Redeploy: Sat Jan 24 11:45:19 WAT 2026
