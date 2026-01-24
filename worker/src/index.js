import { AccessToken } from "livekit-server-sdk";

/**
 * Create an admin JWT that can call LiveKit RoomService APIs.
 * We use roomAdmin: true which is required for UpdateParticipant / MutePublishedTrack.
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
 * Call LiveKit Twirp API: UpdateParticipant
 * This is what actually changes publish permissions server-side (strong enforcement).
 */
async function updateParticipant(env, roomName, identity, permission) {
  const adminJwt = await makeAdminJwt(env, roomName);

  const res = await fetch(
    `${env.LIVEKIT_URL}/twirp/livekit.RoomService/UpdateParticipant`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${adminJwt}`,
      },
      body: JSON.stringify({
        room: roomName,
        identity,
        permission,
      }),
    }
  );

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`UpdateParticipant failed ${res.status}: ${txt}`);
  }

  return res.json();
}

/**
 * Call LiveKit Twirp API: MutePublishedTrack
 * This is optional; we also keep Firestore muted state in your app.
 */
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
    // Basic env validation
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
      const role = (body.role || "listener").toString().trim(); // "host" | "listener"

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

      // Strong enforcement tokens:
      // - host token can publish
      // - listener token cannot publish, until host calls /admin approve
      at.addGrant({
        room: roomName,
        roomJoin: true,
        canSubscribe: true,
        canPublishData: true,
        canPublish: role === "host",
      });

      const token = await at.toJwt();

      return new Response(JSON.stringify({ token, url: env.LIVEKIT_URL, roomName, role }), {
        headers: { "content-type": "application/json" },
      });
    }

    // ---- ROUTE: POST /admin  -> update participant permissions ----
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
      const action = (body.action || "").toString().trim(); // approve|revoke|mute|unmute
      const targetUserId = (body.targetUserId || "").toString().trim();

      if (!leagueId || !action || !targetUserId) {
        return new Response(JSON.stringify({ error: "leagueId, action, targetUserId required" }), {
          status: 400,
          headers: { "content-type": "application/json" },
        });
      }

      const roomName = `league_${leagueId}`;

      try {
        if (action === "approve") {
          const out = await updateParticipant(env, roomName, targetUserId, {
            canPublish: true,
            canSubscribe: true,
            canPublishData: true,
          });
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

        if (action === "revoke") {
          const out = await updateParticipant(env, roomName, targetUserId, {
            canPublish: false,
            canSubscribe: true,
            canPublishData: true,
          });
          return new Response(JSON.stringify({ ok: true, action, out }), {
            headers: { "content-type": "application/json" },
          });
        }

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

    // Anything else
    return new Response("Not found", { status: 404 });
  },
};
// Redeploy: Sat Jan 24 14:10:27 WAT 2026
