'use client';

import { useEffect, useState } from 'react';
import { getFootballNews } from '@/lib/footballHub/footballHubRepository';
import { FootballNewsArticle } from '@/lib/footballHub/types';

export function NewsTab() {
  const [articles, setArticles] = useState<FootballNewsArticle[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getFootballNews()
      .then((a) => !cancelled && setArticles(a))
      .catch((e) => !cancelled && setError(e.message || 'Football news temporarily unavailable. Please try again.'))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, []);

  if (loading) return <p className="text-sm text-gray-400">Loading news...</p>;
  if (error) return <p className="text-sm text-red-400">{error}</p>;
  if (articles.length === 0) return <p className="text-sm text-gray-400">No football news right now.</p>;

  return (
    <div className="space-y-3">
      {articles.map((a, i) => (
        <NewsCard key={`${a.url}-${i}`} article={a} />
      ))}
    </div>
  );
}

function NewsCard({ article }: { article: FootballNewsArticle }) {
  const metaParts = [
    article.sourceName,
    article.publishedAt
      ? article.publishedAt.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
      : null,
  ].filter(Boolean);

  return (
    <a
      href={article.url || undefined}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-start gap-3 bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 hover:border-[#334155] transition-colors"
    >
      {article.imageUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={article.imageUrl} alt="" className="w-20 h-20 rounded-xl object-cover shrink-0" />
      )}
      <div className="min-w-0">
        <p className="text-sm font-bold text-white leading-snug line-clamp-3">{article.title || 'Untitled'}</p>
        {metaParts.length > 0 && <p className="mt-1.5 text-[11px] font-semibold text-gray-400">{metaParts.join(' · ')}</p>}
      </div>
    </a>
  );
}
