/* app/(dashboard)/team/[id]/layout.tsx */
import { Metadata } from 'next';
import { adminDb } from '@/lib/firebase-admin';

type Props = {
  params: { id: string };
};

// Server-rendered Open Graph / Twitter Card metadata for shared team links,
// mirroring leagues/[id]/layout.tsx's generateMetadata pattern exactly —
// this is what makes a link pasted into WhatsApp/Telegram/Facebook/X show
// a rich preview instead of a bare URL.
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const id = params.id;

  try {
    const userDoc = await adminDb.collection('users').doc(id).get();

    if (userDoc.exists) {
      const user = userDoc.data();
      const name = user?.teamName || user?.displayName || 'eSports Player';
      const photo = user?.photoUrl || user?.profileImageUrl || user?.teamImageUrl || '';

      return {
        title: `${name} | eSportlyic`,
        description: 'View this team’s profile, stats, and trophies on eSportlyic.',
        openGraph: {
          title: name,
          description: 'View this team’s profile, stats, and trophies on eSportlyic.',
          images: photo ? [photo] : [],
          type: 'profile',
        },
        twitter: {
          card: 'summary_large_image',
          title: name,
          description: 'View this team’s profile, stats, and trophies on eSportlyic.',
          images: photo ? [photo] : [],
        },
      };
    }
  } catch (error) {
    console.error('Error generating team metadata:', error);
  }

  return {
    title: 'Team Profile | eSportlyic',
    description: 'View this team’s profile, stats, and trophies on eSportlyic.',
  };
}

export default function TeamProfileLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className="w-full">{children}</div>;
}
