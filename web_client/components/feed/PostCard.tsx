'use client';

import { useState, useRef } from 'react';
import { PublicPost } from '@/lib/feed/publicFeedRepository';
import { Glass } from '@/components/ui/Glass';
import { MoreVertical, Trophy, Heart, MessageCircle, Music2, Volume2, VolumeX, ShieldCheck } from 'lucide-react';

interface PostCardProps {
  post: PublicPost;
  isOwner: boolean;
  onLike: () => void;
  onDelete: () => void;
  onOpenLeague: () => void;
}

function timeAgo(ms: number) {
  const diff = Math.floor((Date.now() - ms) / 60000);
  if (diff < 1) return 'Just now';
  if (diff < 60) return `${diff}m`;
  if (diff < 1440) return `${Math.floor(diff / 60)}h`;
  return `${Math.floor(diff / 1440)}d`;
}

export function PostCard({ post, isOwner, onLike, onDelete, onOpenLeague }: PostCardProps) {
  const [isPlaying, setIsPlaying] = useState(false);
  const audioRef = useRef<HTMLAudioElement>(null);

  const toggleAudio = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!audioRef.current) return;
    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  return (
    <Glass className="p-4 sm:p-5 border border-[#1E293B] shadow-xl bg-[#0B1221] hover:border-white/10 transition-colors">
      
      {/* ── Header ── */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-[#1E293B] flex items-center justify-center overflow-hidden shrink-0 border border-white/5">
            {post.authorPhotoUrl ? (
              <img src={post.authorPhotoUrl} alt="Author" className="w-full h-full object-cover" />
            ) : (
              <ShieldCheck className="w-5 h-5 text-gray-500" />
            )}
          </div>
          <div>
            <h4 className="font-bold text-white text-sm leading-tight hover:underline cursor-pointer">
              {post.authorDisplayName || 'User'}
            </h4>
            <p className="text-xs text-gray-500 font-semibold">{timeAgo(post.createdAtMs)}</p>
          </div>
        </div>
        {isOwner && (
          <button onClick={() => { if(confirm('Delete post?')) onDelete(); }} className="p-2 text-gray-500 hover:text-red-500 transition-colors">
            <MoreVertical className="w-4 h-4" />
          </button>
        )}
      </div>

      {/* ── Text Content ── */}
      {post.text && (
        <p className="text-sm text-gray-300 mb-3 whitespace-pre-wrap leading-relaxed">
          {post.text}
        </p>
      )}

      {/* ── Media Content (Images + Audio) ── */}
      {(post.mediaUrl || post.audioUrl) && (
        <div className="mb-4 rounded-2xl overflow-hidden bg-[#070B14] border border-[#1E293B] relative group">
          
          {post.mediaUrl ? (
            <div className="relative max-h-[450px] w-full flex items-center justify-center overflow-hidden bg-black">
              {/* Max Height 450px maps exactly to social media aspect ratios */}
              <img 
                src={post.mediaUrl} 
                alt="Post Media" 
                className="w-full object-cover max-h-[450px]" 
              />
              
              {/* Audio Overlay on Image */}
              {post.audioUrl && (
                <div className="absolute bottom-3 right-3">
                  <button 
                    onClick={toggleAudio}
                    className="p-3 bg-black/60 hover:bg-black/80 backdrop-blur-md rounded-full text-white shadow-lg border border-white/10 transition-transform active:scale-95"
                  >
                    {isPlaying ? <Volume2 className="w-5 h-5 text-[#BEF264]" /> : <VolumeX className="w-5 h-5" />}
                  </button>
                  <audio ref={audioRef} src={post.audioUrl} onEnded={() => setIsPlaying(false)} />
                </div>
              )}
            </div>
          ) : (
            // Audio Only View
            <div className="p-6 bg-gradient-to-br from-[#1E293B] to-[#070B14] flex items-center gap-4">
              <button 
                onClick={toggleAudio}
                className="p-4 bg-[#BEF264] text-[#0F172A] rounded-full shadow-lg hover:brightness-110 transition-transform active:scale-95"
              >
                {isPlaying ? <Volume2 className="w-6 h-6" /> : <Music2 className="w-6 h-6" />}
              </button>
              <div>
                <p className="text-sm font-bold text-white">Audio Clip</p>
                <p className="text-xs text-[#BEF264] font-semibold">{isPlaying ? 'Playing...' : 'Tap to listen'}</p>
              </div>
              <audio ref={audioRef} src={post.audioUrl} onEnded={() => setIsPlaying(false)} />
            </div>
          )}
        </div>
      )}

      {/* ── League Promo Attachment ── */}
      {post.leagueId && (
        <div 
          onClick={onOpenLeague}
          className="mb-4 p-3 rounded-xl bg-[#1E293B]/50 border border-[#1E293B] hover:border-[#BEF264]/50 cursor-pointer transition-colors flex items-center justify-between group"
        >
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-[#BEF264]/10 flex items-center justify-center">
              <Trophy className="w-5 h-5 text-[#BEF264]" />
            </div>
            <div>
              <p className="text-xs font-black text-gray-500 uppercase tracking-widest mb-0.5">Linked Competition</p>
              <p className="text-sm font-bold text-white group-hover:text-[#BEF264] transition-colors">{post.leagueName}</p>
            </div>
          </div>
        </div>
      )}

      {/* ── Actions ── */}
      <div className="flex items-center gap-6 pt-2">
        <button onClick={onLike} className="flex items-center gap-2 text-gray-400 hover:text-red-500 transition-colors group">
          <Heart className="w-5 h-5 group-active:scale-90 transition-transform" />
          <span className="text-xs font-bold">{post.likeCount}</span>
        </button>
        <button className="flex items-center gap-2 text-gray-400 hover:text-sky-400 transition-colors group">
          <MessageCircle className="w-5 h-5 group-active:scale-90 transition-transform" />
          <span className="text-xs font-bold">{post.commentCount}</span>
        </button>
      </div>
    </Glass>
  );
}
