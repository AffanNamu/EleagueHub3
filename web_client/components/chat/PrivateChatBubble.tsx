'use client';

import { PrivateMessage } from '@/lib/models/privateChat';
import { cn } from '@/lib/utils';

export function PrivateChatBubble({ message, isMe }: { message: PrivateMessage; isMe: boolean }) {
  return (
    <div className={cn('flex w-full mb-3', isMe ? 'justify-end' : 'justify-start')}>
      <div
        className={cn(
          'max-w-[75%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed whitespace-pre-wrap break-words',
          isMe
            ? 'bg-brand-lime text-brand-navy rounded-tr-sm font-medium'
            : 'bg-[#0B1221] border border-[#1E293B] text-white rounded-tl-sm',
        )}
      >
        {message.type === 'image' && message.imageUrl && (
          <a href={message.imageUrl} target="_blank" rel="noopener noreferrer" className="block">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={message.imageUrl}
              alt="Attachment"
              className="max-w-[240px] rounded-lg object-cover"
              loading="lazy"
            />
          </a>
        )}

        {message.type === 'voice' && message.voiceUrl && (
          <audio
            controls
            src={message.voiceUrl}
            className={cn('h-10 w-[220px] outline-none rounded-lg', isMe ? 'opacity-90 invert' : '')}
          />
        )}

        {message.type === 'text' && message.text && <span>{message.text}</span>}
      </div>
    </div>
  );
}
