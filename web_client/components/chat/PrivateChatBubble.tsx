'use client';

import { useState, useRef } from 'react';
import { PrivateMessage } from '@/lib/chat/privateChatRepository';
import { PlayCircle, PauseCircle } from 'lucide-react';

interface PrivateChatBubbleProps {
  message: PrivateMessage;
  isMe: boolean;
}

export function PrivateChatBubble({ message, isMe }: PrivateChatBubbleProps) {
  const [isPlaying, setIsPlaying] = useState(false);
  const audioRef = useRef<HTMLAudioElement>(null);

  const toggleVoice = () => {
    if (!audioRef.current) return;
    if (isPlaying) audioRef.current.pause();
    else audioRef.current.play();
    setIsPlaying(!isPlaying);
  };

  let content;

  if (message.type === 'image') {
    content = (
      <div className="rounded-2xl overflow-hidden max-w-[260px] sm:max-w-sm">
        <img src={message.imageUrl} alt="Attachment" className="w-full h-auto object-cover" />
      </div>
    );
  } else if (message.type === 'voice') {
    content = (
      <div className="flex items-center gap-3 w-48 sm:w-56 p-2">
        <button onClick={toggleVoice} className={`p-1 rounded-full ${isMe ? 'text-[#0F172A]' : 'text-[#BEF264]'}`}>
          {isPlaying ? <PauseCircle className="w-8 h-8" /> : <PlayCircle className="w-8 h-8" />}
        </button>
        <div className="flex-1">
          <div className={`h-1.5 rounded-full w-full ${isMe ? 'bg-[#0F172A]/20' : 'bg-[#BEF264]/20'}`} />
          <p className={`text-[10px] mt-1 font-bold ${isMe ? 'text-[#0F172A]/70' : 'text-gray-400'}`}>
            {isPlaying ? 'Playing...' : 'Voice message'}
          </p>
        </div>
        <audio ref={audioRef} src={message.voiceUrl} onEnded={() => setIsPlaying(false)} />
      </div>
    );
  } else {
    content = <p className="text-sm whitespace-pre-wrap leading-relaxed px-1">{message.text}</p>;
  }

  const isBubble = message.type !== 'image';

  return (
    <div className={`flex w-full my-1 ${isMe ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`${
          isBubble 
            ? isMe 
              ? 'bg-[#BEF264] text-[#0F172A] rounded-t-2xl rounded-bl-2xl rounded-br-sm py-2 px-4' 
              : 'bg-[#1E293B] text-white rounded-t-2xl rounded-br-2xl rounded-bl-sm py-2 px-4 border border-white/5'
            : ''
        } max-w-[75%] sm:max-w-md shadow-sm`}
      >
        {content}
      </div>
    </div>
  );
}
