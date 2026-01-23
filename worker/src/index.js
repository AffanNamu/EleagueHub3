import { AccessToken } from "livekit-server-sdk";

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

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
    const role = (body.role || "listener").toString().trim(); // host | listener

    if (!leagueId || !userId) {
      return new Response(JSON.stringify({ error: "leagueId and userId required" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    }

    // IMPORTANT: env vars must exist in production
    if (!env.LIVEKIT_URL || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) {
      return new Response(JSON.stringify({ error: "Worker missing LiveKit env vars" }), {
        status: 500,
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
      canPublish: role === "host",
      canSubscribe: true,
      canPublishData: true,
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
  },
};
