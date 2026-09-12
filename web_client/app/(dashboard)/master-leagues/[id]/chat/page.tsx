'use client';

import { useState, useRef, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
// FIXED: Pointing this to useChat where the updated useOrganizerChat hook actually lives
import { useOrganizerChat, ChatSendReply } from '@/hooks/useChat';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import { useChatModeration } from '@/hooks/useChatModeration';
import { chatMessagePreview } from '@/lib/chat/chatMessagePreview';
import { uploadImageFile, uploadAudioFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Glass } from '@/components/ui/Glass';
import { ChatBubble } from '@/components/chat/ChatBubble';
import { ChatInputBar } from '@/components/chat/ChatInputBar';
import { ArrowLeft, Loader2, MessageSquare, Network } from 'lucide-react';

export default function OrganizerChatScreen() {
  const params = useParams();
  const router = useRouter();
  const masterLeagueId = params.id as string;

  const [sendError, setSendError] = useState('');
  const [replyTo, setReplyTo] = useState<ChatSendReply | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // NEW: uid pulled from the same hook the discipline page already uses,
  // so ownership determination stays consistent app-wide.
  const { workspace, loading: workspaceLoading, uid } = useMasterLeagueDetail(masterLeagueId);
  const { messages, loading: chatLoading, sendMessage, pinMessage, unpinMessage, deleteMessage } = useOrganizerChat(masterLeagueId);

  const isOwner = !!workspace && workspace.ownerId === uid;
  const moderation = useChatModeration(masterLeagueId);
  const chatBlocked = moderation.organizerBanned && !isOwner;
  const chatReadOnly = moderation.organizerMuted && !isOwner;

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [messages]);

  const handleSendText = async (text: string) => {
    setSendError('');
    try {
      await sendMessage({ text, type: 'text', replyTo });
      setReplyTo(null);
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Failed to send message.');
      throw error;
    }
  };

  const handleSendImage = async (file: File) => {
    setSendError('');
    try {
      const { secureUrl } = await uploadImageFile({ file, folder: `eleaguehub/chatrooms/master_leagues/${masterLeagueId}` });
      await sendMessage({ type: 'image', imageUrl: secureUrl, replyTo });
      setReplyTo(null);
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Failed to send image.');
      throw error;
    }
  };

  const handleSendVoice = async (blob: Blob, durationMs: number) => {
    setSendError('');
    try {
      const { secureUrl } = await uploadAudioFile({ file: blob, folder: `chat_voice_messages/master_leagues/${masterLeagueId}` });
      await sendMessage({ type: 'voice', voiceUrl: secureUrl, voiceDurationMs: durationMs, replyTo });
      setReplyTo(null);
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Failed to send voice note.');
      throw error;
    }
  };

  async function handleDelete(messageId: string) {
    if (!confirm('Delete this message?')) return;
    try {
      await deleteMessage(messageId);
    } catch (err) {
      console.error('[OrganizerChatScreen] delete failed:', err);
      alert('Could not delete message.');
    }
  }

  if (workspaceLoading || chatLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  return (
    <div className="flex flex-col h-[calc(100vh-120px)] md:h-[calc(100vh-40px)]">
      <div className="flex items-center gap-4 mb-4 shrink-0">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div className="flex items-center gap-3">
          <div className="p-2 bg-[#38BDF8]/10 rounded-lg border border-[#38BDF8]/20">
            <Network className="w-5 h-5 text-[#38BDF8]" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-white">{workspace?.name || 'Organizer Chat'}</h1>
            <p className="text-xs text-[#38BDF8]">General Community Chat</p>
          </div>
        </div>
      </div>

      <Glass className="flex-1 flex flex-col overflow-hidden p-2 md:p-4">
        <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 scroll-smooth">
          {messages.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-gray-500 gap-2">
              <MessageSquare className="w-10 h-10 opacity-50" />
              <p>No messages yet. Say hello to the community!</p>
            </div>
          ) : (
            messages.map((msg) => (
              <ChatBubble
                key={msg.messageId}
                message={msg}
                canPin={isOwner}
                canDelete={isOwner || msg.senderId === uid}
                canReply={!chatBlocked}
                onPin={() => pinMessage(msg.messageId)}
                onUnpin={() => unpinMessage(msg.messageId)}
                onDelete={() => handleDelete(msg.messageId)}
                onReply={() =>
                  setReplyTo({
                    messageId: msg.messageId,
                    senderName: msg.senderName?.trim() || 'User',
                    text: chatMessagePreview(msg),
                    type: msg.type,
                  })
                }
              />
            ))
          )}
        </div>

        {sendError && <p className="text-xs text-brand-red px-3 pb-1">{sendError}</p>}
        <ChatInputBar
          disabled={chatBlocked || chatReadOnly}
          disabledReason={chatBlocked ? 'You are banned from this organizer chat.' : chatReadOnly ? 'You are muted in this organizer chat.' : undefined}
          sending={false}
          replyTo={replyTo ? { messageId: replyTo.messageId, senderName: replyTo.senderName, previewText: replyTo.text } : null}
          onClearReply={() => setReplyTo(null)}
          onSendText={handleSendText}
          onSendImage={handleSendImage}
          onSendVoice={handleSendVoice}
          accentColor="#38BDF8"
        />
      </Glass>
    </div>
  );
}
