'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { LiveKitRoom, VideoConference, RoomAudioRenderer } from '@livekit/components-react';
import '@livekit/components-styles';
import { doc, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Radio } from 'lucide-react';
import { LiveSession } from '@/types/live';

export default function LiveRoomScreen() {
  const params = useParams();
  const router = useRouter();
  const sessionId = params.id as string;

  const [session, setSession] = useState<LiveSession | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // 1. Fetch Session Data from Firestore
  useEffect(() => {
    const docRef = doc(db, 'live_sessions', sessionId);
    const unsubscribe = onSnapshot(docRef, (snap) => {
      if (snap.exists()) {
        setSession({ id: snap.id, ...snap.data() } as LiveSession);
      }
    });
    return () => unsubscribe();
  }, [sessionId]);

  // 2. Fetch LiveKit Access Token from your Backend (Supabase Edge Function)
  useEffect(() => {
    const fetchToken = async () => {
      if (!session || !auth.currentUser) return;
      
      try {
        // Replace this URL with your actual Supabase Edge Function that generates LiveKit tokens
        const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/generate-livekit-token`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${(await auth.currentUser.getIdToken())}`
          },
          body: JSON.stringify({
            roomName: session.livekitRoomName,
            participantName: auth.currentUser.displayName || 'Spectator',
          })
        });

        const data = await response.json();
        setToken(data.token);
      } catch (error) {
        console.error('Failed to fetch LiveKit token:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchToken();
  }, [session]);

  if (loading || !session) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  const livekitUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

  return (
    <div className="space-y-4">
      {/* Header Panel */}
      <Glass className="p-4 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
            <ArrowLeft className="w-5 h-5 text-white" />
          </button>
          <div>
            <div className="flex items-center gap-2 mb-1">
              <Radio className="w-4 h-4 text-brand-red animate-pulse" />
              <h1 className="text-xl font-bold text-white leading-none">{session.title}</h1>
            </div>
            <p className="text-xs text-gray-400">Hosted by {session.hostName}</p>
          </div>
        </div>

        <div className="px-4 py-2 bg-brand-surfaceDark border border-white/5 rounded-xl font-black text-brand-lime tabular-nums tracking-widest text-lg">
          {session.homeTeamName} {session.homeTeamScore} - {session.awayTeamScore} {session.awayTeamName}
        </div>
      </Glass>

      {/* LiveKit Spectator Component */}
      <Glass className="overflow-hidden min-h-[60vh] relative bg-black">
        {!token || !livekitUrl ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center text-gray-500">
            <Loader2 className="w-8 h-8 animate-spin mb-2" />
            <p>Connecting to secure stream...</p>
          </div>
        ) : (
          <LiveKitRoom
            video={false}
            audio={false}
            token={token}
            serverUrl={livekitUrl}
            data-lk-theme="default"
            style={{ height: '60vh', width: '100%' }}
          >
            {/* The VideoConference component automatically renders shared screen/camera from the Host */}
            <VideoConference />
            <RoomAudioRenderer />
          </LiveKitRoom>
        )}
      </Glass>
    </div>
  );
}
