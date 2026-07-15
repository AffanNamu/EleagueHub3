'use client';

import { useState, useRef, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useGlobalChat } from '@/hooks/useGlobalChat';
import { auth } from '@/lib/firebase';
import { Glass } from '@/components/ui/Glass';
import { ChatBubble } from '@/components/chat/ChatBubble';
import { Loader2, Send, MessageSquare, Globe, Lock, ShieldAlert } from 'lucide-react';
import Link from 'next/link';

export default function GlobalChatScreen() {
  const router = useRouter();
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const { messages, loading: chatLoading, sendMessage, accessStatus, accessLoading, requestAccess } = useGlobalChat();

  const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  const isSuperAdmin = auth.currentUser?.uid === SUPER_ADMIN_UID;
  const hasAccess = isSuperAdmin || accessStatus === 'approved';

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
      alert("Failed to send message.");
    } finally {
      setSending(false);
    }
  };

  if (accessLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  // Render Access Request Screen if not approved
  if (!hasAccess) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[70vh] p-4">
        <Glass className="max-w-md p-8 text-center flex flex-col items-center">
          <Lock className="w-16 h-16 text-brand-lime mb-4" />
          <h2 className="text-2xl font-bold text-white mb-2">Access Required</h2>
          
          <p className="text-gray-400 mb-6">
            {accessStatus === 'pending' 
              ? 'Your request is pending admin approval.' 
              : accessStatus === 'rejected'
              ? 'Your request was rejected. You can request again.'
              : 'Request access to join the global public chatroom.'}
          </p>

          <button
            onClick={requestAccess}
            disabled={accessStatus === 'pending'}
            className="w-full py-3 bg-brand-lime text-brand-navy font-bold rounded-xl hover:bg-brand-lime/90 transition-colors disabled:opacity-50"
          >
            {accessStatus === 'pending' ? 'Pending...' : 'Request Access'}
          </button>
          <p className="text-xs text-gray-500 mt-4">Only approved users can read and send messages.</p>
        </Glass>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-[calc(100vh-120px)] md:h-[calc(100vh-40px)]">
      {/* Header */}
      <div className="flex items-center justify-between mb-4 shrink-0">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-purple-500/10 rounded-lg border border-purple-500/20">
            <Globe className="w-5 h-5 text-purple-400" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-white">Global Chat</h1>
            <p className="text-xs text-purple-400">Platform-wide public chat</p>
          </div>
        </div>
        
        {isSuperAdmin && (
          <Link href="/admin/global-chat-requests" className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors text-gray-400 hover:text-white">
            <ShieldAlert className="w-5 h-5" />
          </Link>
        )}
      </div>

      {/* Chat Area */}
      <Glass className="flex-1 flex flex-col overflow-hidden p-2 md:p-4">
        {chatLoading ? (
          <div className="flex-1 flex justify-center items-center"><Loader2 className="w-8 h-8 text-brand-lime animate-spin" /></div>
        ) : (
          <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 scroll-smooth">
            {messages.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-gray-500 gap-2">
                <Globe className="w-10 h-10 opacity-50" />
                <p>Welcome to the Global Chat!</p>
              </div>
            ) : (
              messages.map((msg) => (
                <ChatBubble key={msg.messageId} message={msg} />
              ))
            )}
          </div>
        )}

        {/* Input Bar */}
        <div className="shrink-0 p-2 mt-2 border-t border-white/5 bg-brand-navySoft rounded-b-2xl">
          <form onSubmit={handleSend} className="flex gap-2">
            <input
              type="text"
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder="Type a message..."
              className="flex-1 bg-brand-surface border border-white/10 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-purple-400 transition-colors"
            />
            <button 
              type="submit"
              disabled={!text.trim() || sending}
              className="px-4 py-3 bg-purple-500 text-white font-bold rounded-xl hover:bg-purple-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[60px]"
            >
              {sending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
            </button>
          </form>
        </div>
      </Glass>
    </div>
  );
}
