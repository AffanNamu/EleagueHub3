'use client';

import { useState, useRef, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useChat } from '@/hooks/useChat';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { ChatBubble } from '@/components/chat/ChatBubble';
import { ArrowLeft, Loader2, Send, MessageSquare } from 'lucide-react';

export default function LeagueChatScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { messages, loading: chatLoading, sendMessage } = useChat(leagueId);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!text.trim() || sending) return;

    setSending(true);
    try {
      await sendMessage(text);
      setText('');
    } catch (error) {
      alert("Failed to send message. Check permissions.");
    } finally {
      setSending(false);
    }
  };

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
              <ChatBubble key={msg.messageId} message={msg} />
            ))
          )}
        </div>

        {/* Input Bar */}
        <div className="shrink-0 p-2 mt-2 border-t border-white/5 bg-brand-navySoft rounded-b-2xl">
          <form onSubmit={handleSend} className="flex gap-2">
            <input
              type="text"
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder="Type a message..."
              className="flex-1 bg-brand-surface border border-white/10 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-brand-lime transition-colors"
            />
            <button 
              type="submit"
              disabled={!text.trim() || sending}
              className="px-4 py-3 bg-brand-lime text-brand-navy rounded-xl hover:bg-brand-lime/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[60px]"
            >
              {sending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
            </button>
          </form>
        </div>
      </Glass>
    </div>
  );
}
