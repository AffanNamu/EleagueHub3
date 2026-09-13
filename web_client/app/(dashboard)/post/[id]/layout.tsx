/* app/(dashboard)/post/[id]/layout.tsx */
import { Metadata } from 'next';
import { adminDb } from '@/lib/firebase-admin';

type Props = {
  params: { id: string };
};

// Server-rendered Open Graph / Twitter Card metadata for shared post links —
// mirrors leagues/[id]/layout.tsx and team/[id]/layout.tsx. Without this, a
// post link pasted into WhatsApp/Telegram/Facebook/X shows a bare URL
// instead of the author's photo/text.
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const id = params.id;

  try {
    const postDoc = await adminDb.collection('public_posts').doc(id).get();

    if (postDoc.exists) {
      const post = postDoc.data();
      if (post?.deleted === true) {
        return {
          title: 'Post unavailable | eSportlyic',
          description: 'This post is no longer available.',
        };
      }

      const authorName = post?.authorDisplayName || 'User';
      const text = (post?.text || '').trim();
      const description = text.length > 160 ? `${text.substring(0, 160)}…` : (text || 'View this post on eSportlyic.');
      const image = post?.mediaUrl || post?.authorPhotoUrl || '';

      return {
        title: `${authorName} on eSportlyic`,
        description,
        openGraph: {
          title: `${authorName} on eSportlyic`,
          description,
          images: image ? [image] : [],
          type: 'website',
        },
        twitter: {
          card: 'summary_large_image',
          title: `${authorName} on eSportlyic`,
          description,
          images: image ? [image] : [],
        },
      };
    }
  } catch (error) {
    console.error('Error generating post metadata:', error);
  }

  return {
    title: 'Post | eSportlyic',
    description: 'View this post on eSportlyic.',
  };
}

export default function PostLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className="w-full">{children}</div>;
}
