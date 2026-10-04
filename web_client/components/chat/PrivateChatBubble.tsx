'use client';

import { useEffect, useState } from 'react';
import { doc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { PrivateMessage } from '@/lib/chat/privateChatRepository';
import { ReactionPicker } from '@/components/reactions/ReactionPicker';
import { ReactionPillBar } from '@/components/reactions/ReactionPillBar';
import { watchReactions, toggleReaction } from '@/lib/reactions/reactionsRepository';
import { ReactionSummary, EMPTY_REACTION_SUMMARY } from '@/types/reactions';

interface PrivateChatBubbleProps {
  message: PrivateMessage;
  isMe: boolean;
  threadId: string;
}

export function PrivateChatBubble({ message, isMe, threadId }: PrivateChatBubbleProps) {
  const messageRef = doc(db, 'private_threads', threadId, 'messages', message.id);
  const [reactions, setReactions] = useState<ReactionSummary>(EMPTY_REACTION_SUMMARY);

  // messageRef is a new object every render; threadId+message.id (already
  // in the deps array) are the real, stable dependencies.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => watchReactions(messageRef, setReactions), [threadId, message.id]);
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
      <div className={`flex flex-col max-w-[75%] sm:max-w-md ${isMe ? 'items-end' : 'items-start'}`}>
        <div
          className={`${
            isBubble
              ? isMe
                ? 'bg-[#BEF264] text-[#0F172A] rounded-t-2xl rounded-bl-2xl rounded-br-sm py-2 px-4'
                : 'bg-[#1E293B] text-white rounded-t-2xl rounded-br-2xl rounded-bl-sm py-2 px-4 border border-white/5'
              : ''
          } shadow-sm`}
        >
          {content}
        </div>
        <div className={`flex items-center gap-1.5 mt-1 ${isMe ? 'flex-row-reverse' : 'flex-row'}`}>
          <ReactionPicker currentEmoji={reactions.myEmoji} onPick={(emoji) => toggleReaction(messageRef, emoji)} />
          <ReactionPillBar summary={reactions} onTapEmoji={(emoji) => toggleReaction(messageRef, emoji)} />
        </div>
      </div>
    </div>
  );
}
