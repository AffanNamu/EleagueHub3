'use client';

// Shared input bar for League Chat and Organizer Chat, mirroring
// chat_input_bar.dart's capabilities: text, image, voice-note recording,
// and a reply-to banner. Both surfaces send through the same three
// callbacks so each page only has to know its own Firestore write shape.

import { useRef, useState } from 'react';
import { Send, Image as ImageIcon, Mic, Square, X, Loader2 } from 'lucide-react';
import { useAudioRecorder } from '@/hooks/useAudioRecorder';

export interface ReplyPreview {
  messageId: string;
  senderName: string;
  previewText: string;
}

interface ChatInputBarProps {
  disabled?: boolean;
  disabledReason?: string;
  sending: boolean;
  replyTo: ReplyPreview | null;
  onClearReply: () => void;
  onSendText: (text: string) => Promise<void>;
  onSendImage: (file: File) => Promise<void>;
  onSendVoice: (blob: Blob, durationMs: number) => Promise<void>;
  accentClassName?: string; // e.g. 'brand-lime' vs '#38BDF8' — kept simple via inline style below
  accentColor?: string;
}

export function ChatInputBar({
  disabled,
  disabledReason,
  sending,
  replyTo,
  onClearReply,
  onSendText,
  onSendImage,
  onSendVoice,
  accentColor = '#BEF264',
}: ChatInputBarProps) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const recorder = useAudioRecorder();

  const isBlocked = !!disabled;
  const isBusy = sending || busy;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isBlocked || isBusy || !text.trim()) return;
    setBusy(true);
    try {
      await onSendText(text.trim());
      setText('');
    } finally {
      setBusy(false);
    }
  };

  const handlePickImage = () => {
    if (isBlocked || isBusy) return;
    fileInputRef.current?.click();
  };

  const handleImageChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setBusy(true);
    try {
      await onSendImage(file);
    } finally {
      setBusy(false);
    }
  };

  const handleMicClick = async () => {
    if (isBlocked || isBusy) return;
    if (!recorder.isRecording) {
      try {
        await recorder.start();
      } catch {
        // permissionDenied surfaces via recorder state
      }
      return;
    }

    setBusy(true);
    try {
      const { blob, durationMs } = await recorder.stop();
      await onSendVoice(blob, durationMs);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="shrink-0 p-2 mt-2 border-t border-white/5 bg-brand-navySoft rounded-b-2xl">
      {isBlocked && disabledReason && (
        <p className="text-xs font-bold text-red-400 px-2 pb-2">{disabledReason}</p>
      )}

      {replyTo && (
        <div className="flex items-center gap-2 mb-2 mx-1 px-3 py-2 bg-white/5 border-l-2 rounded-lg" style={{ borderColor: accentColor }}>
          <div className="flex-1 min-w-0">
            <p className="text-[11px] font-bold" style={{ color: accentColor }}>{replyTo.senderName}</p>
            <p className="text-xs text-gray-400 truncate">{replyTo.previewText}</p>
          </div>
          <button type="button" onClick={onClearReply} className="p-1 text-gray-400 hover:text-white">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {recorder.isRecording ? (
        <div className="flex items-center gap-3 px-2">
          <span className="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse" />
          <span className="text-sm font-bold text-white flex-1">Recording… {recorder.elapsedLabel}</span>
          <button
            type="button"
            onClick={() => recorder.cancel()}
            className="px-3 py-2 rounded-xl border border-white/10 text-gray-300 text-xs font-bold hover:bg-white/5"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleMicClick}
            disabled={isBusy}
            className="px-4 py-2 rounded-xl font-bold text-xs flex items-center gap-2 disabled:opacity-50"
            style={{ backgroundColor: accentColor, color: '#0F172A' }}
          >
            {isBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Square className="w-4 h-4" />}
            Send
          </button>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="flex gap-2 items-center">
          <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleImageChosen} />
          <button
            type="button"
            onClick={handlePickImage}
            disabled={isBlocked || isBusy}
            className="p-3 bg-brand-surface border border-white/10 rounded-xl text-gray-300 hover:text-white disabled:opacity-40 shrink-0"
            title="Send an image"
          >
            <ImageIcon className="w-5 h-5" />
          </button>
          <input
            type="text"
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={isBlocked ? 'Chat unavailable' : 'Type a message...'}
            disabled={isBlocked}
            maxLength={4000}
            className="flex-1 bg-brand-surface border border-white/10 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-white/30 transition-colors disabled:opacity-50"
          />
          <button
            type="button"
            onClick={handleMicClick}
            disabled={isBlocked || isBusy}
            className="p-3 bg-brand-surface border border-white/10 rounded-xl text-gray-300 hover:text-white disabled:opacity-40 shrink-0"
            title="Record a voice note"
          >
            <Mic className="w-5 h-5" />
          </button>
          <button
            type="submit"
            disabled={isBlocked || isBusy || !text.trim()}
            className="px-4 py-3 rounded-xl font-bold flex items-center justify-center min-w-[52px] disabled:opacity-50 disabled:cursor-not-allowed transition-colors shrink-0"
            style={{ backgroundColor: accentColor, color: '#0F172A' }}
          >
            {isBusy ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
          </button>
        </form>
      )}
    </div>
  );
}
