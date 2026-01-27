import { AccessToken } from "livekit-server-sdk";

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function toHttpBase(livekitUrl) {
  // LiveKit client uses ws(s); RoomService APIs require http(s).
  const u = new URL(livekitUrl);
  if (u.protocol === "ws:") u.protocol = "http:";
  if (u.protocol === "wss:") u.protocol = "https:";
  // Remove trailing slashes.
  return u.toString().replace(/\/+$/, "");
}

/**
Admin JWT for calling LiveKit RoomService APIs.
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

async function twirpPost(env, method, body) {
  const base = toHttpBase(env.LIVEKIT_URL);
  const adminJwt = await makeAdminJwt(env, body.room);
  const res = await fetch(`${base}/twirp/livekit.RoomService/${method}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${adminJwt}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`${method} failed ${res.status}: ${txt}`);
  }
  return res.json();
}

async function listParticipants(env, roomName) {
  return twirpPost(env, "ListParticipants", { room: roomName });
}

function isAudioTrackType(trackInfo) {
  const t = trackInfo && trackInfo.type;
  if (t === "AUDIO") return true;
  if (t === 0) return true; // TrackType.AUDIO
  if (typeof t === "string" && t.toUpperCase() === "AUDIO") return true;
  return false;
}

/**
Mute/unmute ALL published audio tracks for an identity.
*/
async function muteAllPublishedAudioTracks(env, roomName, identity, muted) {
  const lp = await listParticipants(env, roomName);
  const participants = Array.isArray(lp && lp.participants) ? lp.participants : [];
  const p = participants.find((x) => x && x.identity === identity);
  if (!p) {
    return { ok: true, room: roomName, identity, muted, tracks: [], note: "participant_not_found" };
  }
  const tracks = Array.isArray(p.tracks) ? p.tracks : [];
  const audioSids = tracks
    .filter((t) => t && isAudioTrackType(t) && typeof t.sid === "string" && t.sid.length > 0)
    .map((t) => t.sid);
  if (audioSids.length === 0) {
    return { ok: true, room: roomName, identity, muted, tracks: [], note: "no_published_audio_tracks" };
  }
  const results = [];
  for (const sid of audioSids) {
    const out = await twirpPost(env, "MutePublishedTrack", {
      room: roomName,
      identity,
      trackSid: sid,
      muted,
    });
    results.push({ trackSid: sid, out });
  }
  return { ok: true, room: roomName, identity, muted, tracks: audioSids, results };
}

export default {
  async fetch(request, env) {
    if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
      return json({ error: "Worker missing LiveKit env vars" }, 500);
    }
    const url = new URL(request.url);

    // ---- ROUTE: POST /  -> issue token ----
    if (url.pathname === "/" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "Invalid JSON" }, 400);
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const userId = (body.userId || "").toString().trim();
      const isHost =
        typeof body.isHost === "boolean"
          ? body.isHost
          : ((body.role || "").toString().trim().toLowerCase() === "host");

      if (!leagueId || !userId) {
        return json({ error: "leagueId and userId required" }, 400);
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
        canPublish: true,
        canPublishData: true,
        roomAdmin: isHost,
      });

      const token = await at.toJwt();
      return json({ token, url: env.LIVEKIT_URL, roomName, isHost });
    }

    // ---- ROUTE: POST /admin  -> moderation (mute/unmute) ----
    if (url.pathname === "/admin" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "Invalid JSON" }, 400);
      }

      const leagueId = (body.leagueId || "").toString().trim();
      const action = (body.action || "").toString().trim(); // mute|unmute
      const targetUserId = (body.targetUserId || "").toString().trim();

      if (!leagueId || !action || !targetUserId) {
        return json({ error: "leagueId, action, targetUserId required" }, 400);
      }

      const roomName = `league_${leagueId}`;
      try {
        if (action === "mute") {
          const out = await muteAllPublishedAudioTracks(env, roomName, targetUserId, true);
          return json({ ok: true, action, out });
        }
        if (action === "unmute") {
          const out = await muteAllPublishedAudioTracks(env, roomName, targetUserId, false);
          return json({ ok: true, action, out });
        }
        return json({ error: "Unknown action" }, 400);
      } catch (e) {
        return json({ error: (e && e.message) || String(e) }, 500);
      }
    }

    return new Response("Not found", { status: 404 });
  },
};
