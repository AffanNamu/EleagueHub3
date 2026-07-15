import React from 'react';
import { ChatMessage } from '@/types/chat';
import { auth } from '@/lib/firebase';
import { cn } from '@/lib/utils';
import { Shield } from 'lucide-react';

export const ChatBubble = ({ message }: { message: ChatMessage }) => {
  const isMe = auth.currentUser?.uid === message.senderId;

  return (
    <div className={cn("flex w-full mb-4", isMe ? "justify-end" : "justify-start")}>
      <div className={cn("flex max-w-[75%] gap-2", isMe ? "flex-row-reverse" : "flex-row")}>
        
        {/* Avatar */}
        <div className="flex-shrink-0">
          {message.senderPhoto ? (
            <img src={message.senderPhoto} alt={message.senderName} className="w-8 h-8 rounded-full object-cover border border-white/10" />
          ) : (
            <div className="w-8 h-8 rounded-full bg-brand-surface border border-white/10 flex items-center justify-center">
              <Shield className="w-4 h-4 text-gray-400" />
            </div>
          )}
        </div>

        {/* Message Body */}
        <div className={cn(
          "flex flex-col", 
          isMe ? "items-end" : "items-start"
        )}>
          <span className="text-xs text-gray-400 mb-1 px-1">{message.senderName}</span>
          <div className={cn(
            "px-4 py-2 rounded-2xl text-sm whitespace-pre-wrap break-words",
            isMe 
              ? "bg-brand-lime text-brand-navy rounded-tr-sm font-medium" 
              : "bg-brand-surface border border-white/5 text-white rounded-tl-sm"
          )}>
            {message.deleted ? <i className="text-opacity-50">Message deleted</i> : message.text}
          </div>
          <span className="text-[10px] text-gray-500 mt-1 px-1">
            {new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </span>
        </div>

      </div>
    </div>
  );
};
