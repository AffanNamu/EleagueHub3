'use client';

import { useState, useRef, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useChat, ChatSendReply } from '@/hooks/useChat';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useChatModeration } from '@/hooks/useChatModeration';
import { checkCanManageLeague } from '@/lib/leagues/canManageLeague';
import { chatMessagePreview } from '@/lib/chat/chatMessagePreview';
import { uploadImageFile, uploadAudioFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Glass } from '@/components/ui/Glass';
import { ChatBubble } from '@/components/chat/ChatBubble';
import { ChatInputBar } from '@/components/chat/ChatInputBar';
import { ArrowLeft, Loader2, MessageSquare } from 'lucide-react';

export default function LeagueChatScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;
  const scrollRef = useRef<HTMLDivElement>(null);

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { messages, loading: chatLoading, sendMessage, pinMessage, unpinMessage, deleteMessage } = useChat(leagueId);

  // Whether the signed-in viewer can moderate (pin/delete-any, bypass
  // mute/ban) this league's chat — computed the same way RoleGuard does,
  // via lib/leagues/canManageLeague.ts. Mirrors league_chat_screen.dart's
  // _canModerateLeague (minus the super-admin uid special case).
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [canModerate, setCanModerate] = useState(false);
  const [replyTo, setReplyTo] = useState<ChatSendReply | null>(null);

  const moderation = useChatModeration(league?.masterLeagueId);
  const chatBlocked = (moderation.globalBanned || moderation.organizerBanned) && !canModerate;
  const chatReadOnly = (moderation.globalMuted || moderation.organizerMuted) && !canModerate;

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  useEffect(() => {
    let cancelled = false;
    async function check() {
      if (!leagueId || !authUid) {
        setCanModerate(false);
        return;
      }
      const result = await checkCanManageLeague(leagueId, authUid);
      if (!cancelled) setCanModerate(result);
    }
    check();
    return () => {
      cancelled = true;
    };
  }, [leagueId, authUid]);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSendText = async (text: string) => {
    await sendMessage({ text, type: 'text', replyTo });
    setReplyTo(null);
  };

  const handleSendImage = async (file: File) => {
    const { secureUrl } = await uploadImageFile({ file, folder: `eleaguehub/chatrooms/leagues/${leagueId}` });
    await sendMessage({ type: 'image', imageUrl: secureUrl, replyTo });
    setReplyTo(null);
  };

  const handleSendVoice = async (blob: Blob, durationMs: number) => {
    const { secureUrl } = await uploadAudioFile({ file: blob, folder: `chat_voice_messages/${leagueId}` });
    await sendMessage({ type: 'voice', voiceUrl: secureUrl, voiceDurationMs: durationMs, replyTo });
    setReplyTo(null);
  };

  async function handleDelete(messageId: string) {
    if (!confirm('Delete this message?')) return;
    try {
      await deleteMessage(messageId);
    } catch (err) {
      console.error('[LeagueChatScreen] delete failed:', err);
      alert('Could not delete message.');
    }
  }

  if (leagueLoading || chatLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  return (
    <div className="flex flex-col h-[calc(100vh-120px)] md:h-[calc(100vh-40px)]">
      {/* Header */}
      <div className="flex items-center gap-4 mb-4 shrink-0">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div className="flex items-center gap-3">
          <div className="p-2 bg-brand-lime/10 rounded-lg">
            <MessageSquare className="w-5 h-5 text-brand-lime" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-white">{league?.name || 'League Chat'}</h1>
            <p className="text-xs text-brand-lime">Live Room</p>
          </div>
        </div>
      </div>

      {/* Chat Area */}
      <Glass className="flex-1 flex flex-col overflow-hidden p-2 md:p-4">

        {/* Messages List */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 scroll-smooth">
          {messages.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-gray-500 gap-2">
              <MessageSquare className="w-10 h-10 opacity-50" />
              <p>No messages yet. Be the first to say hi!</p>
            </div>
          ) : (
            messages.map((msg) => (
              <ChatBubble
                key={msg.messageId}
                message={msg}
                canPin={canModerate}
                canDelete={canModerate || msg.senderId === authUid}
                canReply={!chatBlocked}
                onPin={() => pinMessage(msg.messageId)}
                onUnpin={() => unpinMessage(msg.messageId)}
                onDelete={() => handleDelete(msg.messageId)}
                onReply={() =>
                  setReplyTo({
                    messageId: msg.messageId,
                    senderName: msg.senderName?.trim() || 'Player',
                    text: chatMessagePreview(msg),
                    type: msg.type,
                  })
                }
              />
            ))
          )}
        </div>

        <ChatInputBar
          disabled={chatBlocked || chatReadOnly}
          disabledReason={chatBlocked ? 'You are banned from chat.' : chatReadOnly ? 'You are muted in chat.' : undefined}
          sending={false}
          replyTo={replyTo ? { messageId: replyTo.messageId, senderName: replyTo.senderName, previewText: replyTo.text } : null}
          onClearReply={() => setReplyTo(null)}
          onSendText={handleSendText}
          onSendImage={handleSendImage}
          onSendVoice={handleSendVoice}
          accentColor="#BEF264"
        />
      </Glass>
    </div>
  );
}
