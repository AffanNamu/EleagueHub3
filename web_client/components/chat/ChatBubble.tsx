'use client';

import React, { useEffect, useState } from 'react';
import { ChatMessage } from '@/types/chat';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc } from 'firebase/firestore';
import { cn } from '@/lib/utils';
import { Shield, BadgeCheck, Pin, PinOff, Trash2 } from 'lucide-react';

type ExtendedChatMessage = ChatMessage & {
  imageUrl?: string;
  voiceUrl?: string;
  type?: string;
};

interface ChatBubbleProps {
  message: ExtendedChatMessage;
  /** Show the pin/unpin button. Caller decides eligibility (organizer-only). */
  canPin?: boolean;
  /** Show the delete button. Caller decides eligibility (organizer OR own message). */
  canDelete?: boolean;
  onPin?: () => void;
  onUnpin?: () => void;
  onDelete?: () => void;
}

export const ChatBubble = ({ message, canPin, canDelete, onPin, onUnpin, onDelete }: ChatBubbleProps) => {
  const isMine = auth.currentUser?.uid === message.senderId;
  const [badges, setBadges] = useState({ staff: false, organizer: false, green: false });

  // Safely fetch the sender's badge status from their user profile
  useEffect(() => {
    const fetchBadges = async () => {
      if (!message.senderId) return;
      try {
        const userDoc = await getDoc(doc(db, 'users', message.senderId));
        if (userDoc.exists()) {
          const data = userDoc.data();
          const v = data.verification || {};
          setBadges({
            staff: v.staffVerified === true,
            organizer: v.organizerVerified === true || data.isVerifiedOrganizer === true,
            green: v.greenVerified === true || data.verifiedBadge === true,
          });
        }
      } catch (err) {
        // Silently ignore
      }
    };
    fetchBadges();
  }, [message.senderId]);

  const renderBadge = () => {
    if (badges.staff) {
      return (
        <span title="Staff / Ambassador" className="flex items-center ml-1">
          <BadgeCheck className="w-3.5 h-3.5 text-[#E9D5FF] fill-[#9333EA] drop-shadow-[0_0_5px_rgba(147,51,234,0.9)]" />
        </span>
      );
    }
    if (badges.organizer) {
      return (
        <span title="Official Organizer" className="flex items-center ml-1">
          <BadgeCheck className="w-3.5 h-3.5 text-[#FEF08A] fill-[#F59E0B] drop-shadow-[0_0_5px_rgba(245,158,11,0.9)]" />
        </span>
      );
    }
    if (badges.green) {
      return (
        <span title="Verified User" className="flex items-center ml-1">
          <BadgeCheck className="w-3.5 h-3.5 text-[#BBF7D0] fill-[#22C55E] drop-shadow-[0_0_5px_rgba(34,197,94,0.9)]" />
        </span>
      );
    }
    return null;
  };

  // NEW: only offer actions on messages that aren't already deleted.
  const showActions = !message.deleted && (canPin || canDelete);

  return (
    <div className={cn("flex w-full mb-4 group", isMine ? "justify-end" : "justify-start")}>
      <div className={cn("flex max-w-[85%] md:max-w-[75%] gap-2.5", isMine ? "flex-row-reverse" : "flex-row")}>
        
        {/* Avatar */}
        {!isMine && (
          <div className="flex-shrink-0 mt-4">
            {message.senderPhoto ? (
              <img src={message.senderPhoto} alt={message.senderName} className="w-8 h-8 rounded-full object-cover border border-[#1E293B]" />
            ) : (
              <div className="w-8 h-8 rounded-full bg-[#1E293B] border border-white/10 flex items-center justify-center">
                <Shield className="w-4 h-4 text-gray-400" />
              </div>
            )}
          </div>
        )}

        {/* Message Body */}
        <div className={cn(
          "flex flex-col", 
          isMine ? "items-end" : "items-start"
        )}>
          
          {/* Name & Badge Container */}
          {!isMine && (
            <span className="text-[11px] font-bold text-gray-500 mb-1 px-1 flex items-center">
              {message.senderName}
              {renderBadge()}
            </span>
          )}

          {/* NEW: wrapped in a relative container so the hover action
              bar can be positioned beside the bubble without disturbing
              its own layout. */}
          <div className="relative">
            <div className={cn(
              "px-4 py-2.5 text-sm leading-relaxed whitespace-pre-wrap break-words flex flex-col gap-2 relative shadow-md",
              isMine 
                ? "bg-brand-lime text-brand-navy rounded-2xl rounded-tr-sm font-medium" 
                : "bg-[#0B1221] border border-[#1E293B] text-white rounded-2xl rounded-tl-sm"
            )}>
              {message.pinned && (
                <Pin className={`w-3 h-3 absolute -top-1.5 -right-1.5 ${isMine ? 'text-brand-navy' : 'text-[#38BDF8]'}`} />
              )}
              
              {message.deleted ? (
                <i className="opacity-50 text-xs">Message deleted</i>
              ) : (
                <>
                  {/* Image Attachment Rendering */}
                  {message.imageUrl && message.type === 'image' && (
                    <a href={message.imageUrl} target="_blank" rel="noopener noreferrer" className="block w-full">
                      <img 
                        src={message.imageUrl} 
                        alt="Chat Attachment" 
                        className="w-full max-w-[240px] md:max-w-xs rounded-lg object-cover cursor-pointer hover:opacity-90 transition-opacity border border-black/10"
                        loading="lazy"
                      />
                    </a>
                  )}

                  {/* Voice Note Rendering */}
                  {message.voiceUrl && message.type === 'voice' && (
                    <audio 
                      controls 
                      src={message.voiceUrl} 
                      className={cn(
                        "h-10 w-[200px] md:w-[240px] outline-none rounded-lg",
                        isMine ? "opacity-90 invert" : "opacity-100"
                      )} 
                    />
                  )}
                  
                  {/* Text Content */}
                  {message.text && <span>{message.text}</span>}
                </>
              )}
            </div>

            {/* NEW: moderation action bar — appears on hover, only when
                the caller says this viewer is allowed to do something. */}
            {showActions && (
              <div
                className={cn(
                  'absolute top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1',
                  isMine ? '-left-[70px]' : '-right-[70px]',
                )}
              >
                {canPin && (
                  <button
                    onClick={message.pinned ? onUnpin : onPin}
                    title={message.pinned ? 'Unpin' : 'Pin'}
                    className="w-7 h-7 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300"
                  >
                    {message.pinned ? <PinOff className="w-3.5 h-3.5" /> : <Pin className="w-3.5 h-3.5" />}
                  </button>
                )}
                {canDelete && (
                  <button
                    onClick={onDelete}
                    title="Delete"
                    className="w-7 h-7 flex items-center justify-center rounded-full bg-white/5 hover:bg-red-500/20 text-slate-300 hover:text-red-400"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            )}
          </div>
          
          <span className={cn("text-[10px] text-gray-500 mt-1 px-1", isMine ? "text-right" : "text-left")}>
            {new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </span>
        </div>

      </div>
    </div>
  );
};