'use client';

import { PrivateMessage } from '@/lib/chat/privateChatRepository';

interface PrivateChatBubbleProps {
  message: PrivateMessage;
  isMe: boolean;
}

export function PrivateChatBubble({ message, isMe }: PrivateChatBubbleProps) {
  let content;

  if (message.type === 'image') {
    content = (
      <div className="rounded-2xl overflow-hidden max-w-[260px] sm:max-w-sm">
        <img src={message.imageUrl} alt="Attachment" className="w-full h-auto object-cover" />
      </div>
    );
  } else if (message.type === 'voice') {
    content = (
      <audio
        controls
        src={message.voiceUrl}
        className={`h-10 w-[220px] sm:w-[256px] outline-none rounded-lg ${isMe ? 'opacity-90 invert' : 'opacity-100'}`}
      />
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
