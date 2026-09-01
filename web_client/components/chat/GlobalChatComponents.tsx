'use client';

import { useState, useRef } from 'react';
import { ChatMessage } from '@/lib/chat/chatRepository';
import { Glass } from '@/components/ui/Glass';
import { PlayCircle, PauseCircle, Copy, Reply, Pin as PushPin, Trash2, ShieldCheck, FileCode } from 'lucide-react';

// ── BUBBLE ──
export function GlobalChatBubble({ 
  message, isMe, onSelect, selected, onReply, onPin, onDelete, isAdmin 
}: { 
  message: ChatMessage; isMe: boolean; selected: boolean; onSelect: () => void; onReply: () => void; onPin?: () => void; onDelete?: () => void; isAdmin: boolean; 
}) {
  const [isPlaying, setIsPlaying] = useState(false);
  const audioRef = useRef<HTMLAudioElement>(null);

  const toggleVoice = (e: any) => {
    e.stopPropagation();
    if (!audioRef.current) return;
    if (isPlaying) audioRef.current.pause();
    else audioRef.current.play();
    setIsPlaying(!isPlaying);
  };

  const getPreview = () => {
    if (message.deleted) return 'This message was deleted';
    if (message.type === 'image') return message.text || '📷 Photo';
    if (message.type === 'voice') return message.text || '🎤 Voice message';
    if (message.type === 'code') return '💻 Code block';
    return message.text;
  };

  let content;
  if (message.deleted) {
    content = <p className="text-sm italic text-gray-500 font-bold">This message was deleted</p>;
  } else if (message.type === 'image') {
    content = (
      <div className="rounded-xl overflow-hidden max-w-[260px] sm:max-w-xs border border-white/5">
        <img src={message.imageUrl} alt="Attachment" className="w-full h-auto object-cover" />
        {message.text && <p className="text-sm mt-2 px-1">{message.text}</p>}
      </div>
    );
  } else if (message.type === 'voice') {
    content = (
      <div className="flex items-center gap-3 w-48 sm:w-56 p-1">
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
  } else if (message.type === 'code') {
    content = (
      <div className="bg-[#070B14] p-3 rounded-xl border border-white/10 w-full overflow-x-auto">
        <pre className="text-xs font-mono text-gray-300">{message.text}</pre>
      </div>
    );
  } else {
    content = <p className="text-sm whitespace-pre-wrap leading-relaxed px-1 font-medium">{message.text}</p>;
  }

  const time = new Date(message.createdAtMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  return (
    <div className={`flex w-full my-2 group ${isMe ? 'justify-end' : 'justify-start'}`}>
      
      {/* Context Actions (Hover/Select) */}
      <div className={`flex items-center gap-1 px-2 opacity-0 group-hover:opacity-100 transition-opacity ${isMe ? 'order-1' : 'order-2'} ${selected ? 'opacity-100' : ''}`}>
        <button onClick={onReply} className="p-1.5 text-gray-500 hover:text-sky-400"><Reply className="w-4 h-4"/></button>
        {(isAdmin || isMe) && <button onClick={onDelete} className="p-1.5 text-gray-500 hover:text-red-500"><Trash2 className="w-4 h-4"/></button>}
        {(isAdmin || isMe) && <button onClick={onPin} className="p-1.5 text-gray-500 hover:text-[#BEF264]"><PushPin className="w-4 h-4"/></button>}
      </div>

      <div 
        onClick={onSelect}
        className={`max-w-[75%] sm:max-w-md shadow-sm transition-all cursor-pointer ${
          isMe 
            ? 'bg-[#BEF264] text-[#0F172A] rounded-t-2xl rounded-bl-2xl rounded-br-sm py-2.5 px-4' 
            : 'bg-[#1E293B] text-white rounded-t-2xl rounded-br-2xl rounded-bl-sm py-2.5 px-4 border border-white/5'
        } ${selected ? 'ring-2 ring-sky-400 shadow-sky-500/20' : ''}`}
      >
        {!isMe && (
          <div className="flex items-center gap-2 mb-2">
            <img src={message.senderPhoto || '/placeholder.png'} className="w-5 h-5 rounded-full object-cover bg-gray-800" />
            <span className="text-xs font-black opacity-80">{message.senderName || 'Player'}</span>
          </div>
        )}

        {message.replyToMessageId && (
          <div className="mb-2 p-2 rounded-lg bg-black/10 border-l-2 border-current opacity-80">
            <p className="text-[10px] font-black uppercase mb-0.5">{message.replyToSenderName}</p>
            <p className="text-xs truncate font-semibold">{message.replyToText}</p>
          </div>
        )}

        {content}

        <div className={`text-[10px] font-bold mt-1.5 text-right ${isMe ? 'opacity-60' : 'text-gray-500'}`}>
          {time}
        </div>
      </div>
    </div>
  );
}

// ── PINNED BAR ──
export function PinnedMessageBar({ message, onUnpin, isAdmin }: { message: ChatMessage; onUnpin: () => void; isAdmin: boolean }) {
  return (
    <Glass className="mx-4 my-2 p-3 bg-[#0B1221] border-[#1E293B] rounded-2xl flex items-start gap-3 shadow-lg">
      <PushPin className="w-5 h-5 text-[#BEF264] mt-0.5 shrink-0" />
      <div className="flex-1 min-w-0">
        <p className="text-[10px] font-black text-[#BEF264] uppercase tracking-widest mb-0.5">Pinned Message</p>
        <p className="text-xs font-bold text-gray-400 truncate">{message.senderName}</p>
        <p className="text-sm font-semibold text-white truncate">{message.text || 'Media Message'}</p>
      </div>
      {isAdmin && <button onClick={onUnpin} className="text-gray-500 hover:text-red-500 p-1"><Trash2 className="w-4 h-4"/></button>}
    </Glass>
  );
}
