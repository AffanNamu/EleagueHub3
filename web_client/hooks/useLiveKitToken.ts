import { useState, useEffect } from 'react';
import { auth } from '@/lib/firebase';

export function useLiveKitToken(roomName: string, isHost: boolean = false) {
  const [token, setToken] = useState<string | null>(null);
  const [livekitUrl, setLivekitUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchToken = async () => {
      if (!roomName || !auth.currentUser) return;
      
      try {
        const workerUrl = process.env.NEXT_PUBLIC_EDGE_WORKER_URL;
        if (!workerUrl) throw new Error("Worker URL not configured");

        const idToken = await auth.currentUser.getIdToken();

        const response = await fetch(`${workerUrl}/`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${idToken}`
          },
          body: JSON.stringify({
            userId: auth.currentUser.uid,
            roomName: roomName,
            role: isHost ? 'host' : 'participant'
          })
        });

        const data = await response.json();

        if (!response.ok) {
          throw new Error(data.error || 'Failed to fetch token');
        }

        setToken(data.token);
        setLivekitUrl(data.url);
      } catch (err: any) {
        console.error('LiveKit Token Error:', err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchToken();
  }, [roomName, isHost]);

  return { token, livekitUrl, loading, error };
}
