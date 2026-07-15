'use client';

import { useParams, useRouter } from 'next/navigation';
import { useLiveKitToken } from '@/hooks/useLiveKitToken';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Mic, PhoneOff, Users, ArrowLeft } from 'lucide-react';
import { LiveKitRoom, RoomAudioRenderer, AudioConference, ControlBar } from '@livekit/components-react';
import '@livekit/components-styles';

export default function VoiceCallScreen() {
  const params = useParams();
  const router = useRouter();
  const callId = (params.id as string).toUpperCase(); // e.g. 8-char code

  // The LiveKit hook automatically hits your edge worker with roomName: call_XXXX
  const { token, livekitUrl, loading, error } = useLiveKitToken(`call_${callId}`, false);

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  if (error) return <div className="text-center py-20 text-brand-red font-bold">Failed to join call: {error}</div>;

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Mic className="w-6 h-6 text-brand-lime" /> Drop-in Audio
          </h1>
          <p className="text-xs text-brand-lime font-mono tracking-widest mt-1">CALL ID: {callId}</p>
        </div>
      </div>

      <Glass className="p-2 md:p-4 overflow-hidden h-[600px] flex flex-col bg-brand-navy border border-brand-lime/20">
        {token && livekitUrl && (
          <LiveKitRoom
            video={false}
            audio={true}
            token={token}
            serverUrl={livekitUrl}
            connectOptions={{ autoSubscribe: true }}
            onDisconnected={() => router.push('/leagues')}
            className="flex-1 flex flex-col"
          >
            <div className="flex-1 overflow-y-auto p-4">
               {/* LiveKit Pre-built Audio Grid */}
               <AudioConference />
            </div>
            
            <div className="p-4 bg-black/40 rounded-xl mt-2 shrink-0">
               <ControlBar 
                 variation="minimal" 
                 controls={{ microphone: true, camera: false, screenShare: false, chat: false }}
               />
            </div>
            <RoomAudioRenderer />
          </LiveKitRoom>
        )}
      </Glass>
    </div>
  );
}
