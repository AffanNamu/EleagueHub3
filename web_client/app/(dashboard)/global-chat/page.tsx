'use client';

import { useState, useRef, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { useGlobalChat, useGlobalChatAccess } from '@/hooks/useGlobalChat';
import { requestGlobalChatAccessWeb, sendGlobalMessageWeb, pinGlobalMessageWeb, softDeleteGlobalMessageWeb, ChatMessage } from '@/lib/chat/chatRepository';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { GlobalChatBubble, PinnedMessageBar } from '@/components/chat/GlobalChatComponents';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Send, Image as ImageIcon, Mic, X, ShieldAlert, Code } from 'lucide-react';

const SUPER_ADMIN_UID = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

export default function GlobalChatScreen() {
  const router = useRouter();
  const [authUid, setAuthUid] = useState<string>('');
  
  useEffect(() => {
    const unsub = auth.onAuthStateChanged(u => setAuthUid(u?.uid || ''));
    return () => unsub();
  }, []);

  const { messages, pinnedMessage, loading } = useGlobalChat();
  const { status, moderation, isAdmin } = useGlobalChatAccess(authUid);
  
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [codeMode, setCodeMode] = useState(false);
  const [replyTo, setReplyTo] = useState<ChatMessage | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const fileRef = useRef<HTMLInputElement>(null);
  const audioRef = useRef<HTMLInputElement>(null);

  const isSuperAdmin = authUid === SUPER_ADMIN_UID;
  const hasAccess = isSuperAdmin || status === 'approved';

  const handleRequestAccess = async () => {
    if (!auth.currentUser) return router.push('/login');
    setSending(true);
    await requestGlobalChatAccessWeb(authUid, auth.currentUser.displayName || 'User', auth.currentUser.photoURL || '');
    setSending(false);
  };

  const handleSendText = async () => {
    if (!text.trim() || sending || moderation.muted || moderation.banned) return;
    setSending(true);
    try {
      await sendGlobalMessageWeb({
        senderId: authUid,
        senderName: auth.currentUser!.displayName || 'Player',
        senderPhoto: auth.currentUser!.photoURL || '',
        text: text.trim(),
        type: codeMode ? 'code' : 'text',
        replyToMessageId: replyTo?.messageId || '',
        replyToSenderName: replyTo?.senderName || '',
        replyToText: replyTo?.text || replyTo?.type || '',
      });
      setText(''); setReplyTo(null); setCodeMode(false);
    } catch (err) {
      alert("Failed to send");
    } finally {
      setSending(false);
    }
  };

  const handleFileUpload = async (file: File | null, isVoice: boolean) => {
    if (!file || sending || moderation.muted || moderation.banned) return;
    setSending(true);
    try {
      const res = await uploadImageFile({ file, folder: 'eleaguehub/chatrooms/global', resourceType: isVoice ? 'video' : 'image' });
      await sendGlobalMessageWeb({
        senderId: authUid,
        senderName: auth.currentUser!.displayName || 'Player',
        senderPhoto: auth.currentUser!.photoURL || '',
        type: isVoice ? 'voice' : 'image',
        imageUrl: !isVoice ? res.secureUrl : '',
        voiceUrl: isVoice ? res.secureUrl : '',
        replyToMessageId: replyTo?.messageId || '',
        replyToSenderName: replyTo?.senderName || '',
        replyToText: replyTo?.text || replyTo?.type || '',
      });
      setReplyTo(null);
    } catch (err) {
      alert("Upload failed");
    } finally {
      setSending(false);
    }
  };

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" /></div>;

  if (!hasAccess) {
    return (
      <div className="max-w-xl mx-auto pt-20 px-4">
        <Glass className="p-8 bg-[#0B1221] border-[#1E293B] rounded-3xl text-center shadow-2xl">
          <ShieldAlert className="w-12 h-12 text-[#BEF264] mx-auto mb-4" />
          <h2 className="text-xl font-black text-white mb-2">Access Required</h2>
          <p className="text-sm font-medium text-gray-400 mb-6">
            {status === 'pending' ? 'Your request is pending admin approval.' : status === 'rejected' ? 'Your request was rejected. You can request again.' : 'Request access to join the global public chatroom.'}
          </p>
          <button onClick={handleRequestAccess} disabled={sending} className="px-6 py-3 w-full bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 disabled:opacity-50">
            {sending ? <Loader2 className="w-5 h-5 animate-spin mx-auto"/> : (status === 'pending' ? 'Pending...' : 'Request Access')}
          </button>
        </Glass>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-[calc(100vh-5rem)] max-w-3xl mx-auto bg-[#070B14] md:border-x md:border-[#1E293B]">
      
      {/* ── HEADER ── */}
      <div className="flex items-center justify-between p-4 border-b border-[#1E293B] bg-[#0B1221]">
        <div className="flex items-center gap-3">
          <button onClick={() => router.back()} className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-white transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-black text-white">Global Chat</h1>
        </div>
        {isSuperAdmin && (
          <button onClick={() => router.push('/admin/global-chat-requests')} className="text-xs font-black text-[#BEF264] bg-[#BEF264]/10 px-3 py-1.5 rounded-lg border border-[#BEF264]/30 hover:bg-[#BEF264]/20">
            Admin Requests
          </button>
        )}
      </div>

      {/* ── MODERATION BANNERS ── */}
      {moderation.banned && <div className="p-3 bg-red-500/10 text-red-500 text-xs font-bold text-center border-b border-red-500/20">You are banned from Global Chat.</div>}
      {moderation.muted && !moderation.banned && <div className="p-3 bg-amber-500/10 text-amber-500 text-xs font-bold text-center border-b border-amber-500/20">You are muted. You can read but cannot send messages.</div>}

      {/* ── PINNED MESSAGE ── */}
      {pinnedMessage && <PinnedMessageBar message={pinnedMessage} isAdmin={isAdmin || isSuperAdmin} onUnpin={() => pinGlobalMessageWeb(pinnedMessage.messageId, '', pinnedMessage.messageId)} />}

      {/* ── MESSAGES LIST ── */}
      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar flex flex-col-reverse">
        {messages.map(m => (
          <GlobalChatBubble 
            key={m.messageId} message={m} isMe={m.senderId === authUid} isAdmin={isAdmin || isSuperAdmin}
            selected={selectedId === m.messageId} onSelect={() => setSelectedId(selectedId === m.messageId ? null : m.messageId)}
            onReply={() => { setReplyTo(m); setSelectedId(null); }}
            onPin={() => { pinGlobalMessageWeb(m.messageId, authUid, pinnedMessage?.messageId || null); setSelectedId(null); }}
            onDelete={() => { softDeleteGlobalMessageWeb(m.messageId, authUid); setSelectedId(null); }}
          />
        ))}
      </div>

      {/* ── INPUT BAR ── */}
      {!(moderation.banned || moderation.muted) && (
        <div className="p-4 bg-[#0B1221] border-t border-[#1E293B]">
          
          {replyTo && (
            <div className="mb-3 flex items-center justify-between p-3 bg-[#1E293B] rounded-xl border-l-4 border-[#BEF264]">
              <div>
                <p className="text-[10px] font-black uppercase text-[#BEF264] mb-0.5">Replying to {replyTo.senderName}</p>
                <p className="text-xs text-gray-300 font-semibold truncate max-w-xs">{replyTo.text || replyTo.type}</p>
              </div>
              <button onClick={() => setReplyTo(null)} className="text-gray-500 hover:text-white"><X className="w-4 h-4"/></button>
            </div>
          )}

          <div className="flex items-center gap-2">
            <button onClick={() => setCodeMode(!codeMode)} className={`w-10 h-10 flex items-center justify-center rounded-xl border transition-colors ${codeMode ? 'bg-[#BEF264]/20 border-[#BEF264]/50 text-[#BEF264]' : 'bg-[#1E293B]/50 border-white/5 text-gray-400 hover:text-white'}`}>
              <Code className="w-4 h-4" />
            </button>
            
            <label className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-gray-400 hover:text-white cursor-pointer shrink-0 transition-colors border border-white/5">
              <ImageIcon className="w-4 h-4" />
              <input type="file" accept="image/*" className="hidden" onChange={e => handleFileUpload(e.target.files?.[0] || null, false)} disabled={sending} />
            </label>

            <label className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-gray-400 hover:text-white cursor-pointer shrink-0 transition-colors border border-white/5">
              <Mic className="w-4 h-4" />
              <input type="file" accept="audio/*" className="hidden" onChange={e => handleFileUpload(e.target.files?.[0] || null, true)} disabled={sending} />
            </label>
            
            <input
              value={text} onChange={e => setText(e.target.value)} onKeyDown={e => e.key === 'Enter' && handleSendText()}
              placeholder={codeMode ? "Paste code..." : "Message..."} disabled={sending}
              className={`flex-1 px-4 py-3 rounded-2xl bg-[#1E293B]/50 border border-white/5 text-sm font-semibold text-white placeholder:text-gray-500 outline-none focus:border-[#BEF264]/50 transition-colors ${codeMode ? 'font-mono' : ''}`}
            />
            
            <button onClick={handleSendText} disabled={sending || !text.trim()} className="w-12 h-12 flex items-center justify-center rounded-2xl bg-[#BEF264] text-[#0F172A] shrink-0 disabled:opacity-50 hover:brightness-110 shadow-lg shadow-[#BEF264]/20 transition-all">
              {sending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
